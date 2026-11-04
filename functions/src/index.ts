/**
 * 漂流瓶云函数（v2，TypeScript）
 * 路由字段 deliveryState（floating/delivered/held/done）决定瓶子流向；status 仅用于给发送者展示。
 *  - 只匹配异性、±10 岁、未互相拉黑、未封禁的真实用户
 *  - 只要存在符合条件的真实用户，瓶子必然投递给真人；放走/超时后继续投递下一位
 *  - 每个瓶子最多 3 人回复（达到上限后停止漂流）
 *  - 灯塔守望者（AI，明确标注）只在这片海只有你一位用户时回复
 */
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { checkImage, reviewId } from "./imageModeration";
import { sendPush, CHAT_GAP } from "./push";
import { moderate, moderateTextLocal } from "./moderation";
import { verifyTransaction, TIER_QUOTA, EXCLUSIVE_STYLES, isUnlimited, Tier } from "./appstore";
import { t, reason, resolveLocale } from "./i18n";

admin.initializeApp();
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const REGION = "europe-west1";
const NEW_ACCOUNT_THROWS = 3, AGE = 10, NO_REPLY_HOURS = 24, MAX_REPLIERS = 3;
const AI_ID = "ai_lighthouse";
const MAX_BOTTLE = 200, MAX_REPLY = 500;
/** 近似“用户可见字符”计数（与 Swift String.count 接近）：合并 ZWJ emoji、去掉变体选择符/肤色/组合附加符 */
const charCount = (s: string) =>
  Array.from(s.replace(/\u200d\p{Extended_Pictographic}/gu, "").replace(/[\ufe0e\ufe0f\u{1F3FB}-\u{1F3FF}\u0300-\u036f\u{E0020}-\u{E007F}]/gu, "")).length;
/** 请求语言优先，其次用户资料里的 locale，默认 en */
const locOf = (req: CallableRequest, u?: any) => resolveLocale(req.data?.locale ?? u?.locale);

type Kind = "human" | "ai" | "system";
const dayKey = () => new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10).replace(/-/g, "");
const opposite = (g: string) => (g === "male" ? "female" : "male");
const toDate = (v: any): Date | null => (v?.toDate ? v.toDate() : v instanceof Date ? v : null);

function requireUid(req: CallableRequest): string {
  const uid = req.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", t(req.data?.locale, "err.login"));
  return uid;
}

async function getUser(uid: string, locale?: string) {
  const d = await db.doc(`users/${uid}`).get();
  if (!d.exists) throw new HttpsError("failed-precondition", t(locale, "err.profile"));
  const u: any = { id: uid, ...d.data() };
  if (u.banned) throw new HttpsError("permission-denied", t(locale ?? u.locale, "err.banned"));
  if (u.deviceId && (await db.doc(`bannedDevices/${u.deviceId}`).get()).exists) throw new HttpsError("permission-denied", t(locale ?? u.locale, "err.device_banned"));
  return u;
}

function isMemberActive(u: any): boolean {
  const exp = toDate(u.memberExpiresAt);
  return !!u.isMember && !!exp && exp.getTime() > Date.now();
}
/** 当前有效等级：过期即视为 free */
function tierOf(u: any): Tier {
  if (!isMemberActive(u)) return "free";
  return (u.memberTier in TIER_QUOTA ? u.memberTier : "free") as Tier;
}

function dailyLimit(u: any, field: "throws" | "picks"): number {
  const created = toDate(u.serverCreatedAt) ?? new Date();
  const isNew = Date.now() - created.getTime() < 24 * 3600e3;
  if (field === "throws" && isNew) return NEW_ACCOUNT_THROWS; // 新账号 24 小时内每天最多扔 3 个（防刷）
  return TIER_QUOTA[tierOf(u)];
}

/** 配额按设备计数（重装 App、换匿名账号不会重置）；无设备 ID 时退回按 uid */
const quotaRef = (u: any) => db.doc(`deviceQuota/${u.deviceId ? "d_" + u.deviceId : "u_" + u.id}_${dayKey()}`);

async function consumeQuota(u: any, field: "throws" | "picks") {
  const ref = quotaRef(u);
  const limit = dailyLimit(u, field);
  return db.runTransaction(async (t) => {
    const cur = ((await t.get(ref)).data()?.[field] as number) ?? 0;
    if (cur >= limit) return false;
    t.set(ref, { [field]: cur + 1 }, { merge: true });
    return true;
  });
}

function mutuallyOk(a: any, b: any) {
  return !(a.blockedUserIds ?? []).includes(b.id) && !(b.blockedUserIds ?? []).includes(a.id) && !b.banned && !a.banned;
}

async function eligibleUsers(user: any, exclude: string[] = []) {
  const snap = await db.collection("users")
    .where("gender", "==", opposite(user.gender))
    .where("birthYear", ">=", user.birthYear - AGE)
    .where("birthYear", "<=", user.birthYear + AGE).get();
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as any) }))
    .filter((u) => !exclude.includes(u.id) && mutuallyOk(user, u));
}

/** key 为 i18n key（notice.* / ai.first_visitor），按收件人 locale 本地化；同时保存 key/args 便于客户端重新本地化 */
async function notify(uid: string, bottleId: string, key: string, kind: Kind, event = "status", ...args: (string | number)[]) {
  const loc = (await db.doc(`users/${uid}`).get()).data()?.locale;
  const message = t(loc, key, ...args);
  await db.collection(`users/${uid}/notices`).add({ bottleId, message, messageKey: key, messageArgs: args, kind, event, read: false, createdAt: new Date() });
  // 回信总是推送；其他状态（被捡起/扔回/保留等）每个瓶子 10 分钟内最多一条
  await sendPush(uid, { title: kind === "ai" ? t(loc, "push.ai") : event === "replied" ? t(loc, "push.replied") : t(loc, "push.new_msg"),
    body: message, key: event === "replied" ? `reply_${bottleId}_${Date.now()}` : `bottle_${bottleId}`,
    gapMs: event === "replied" ? 0 : 10 * 60e3, data: { bottleId, event } });
}

/** 投递给一位符合条件的真人（当前持有瓶子最少者优先）；没有则 floating */
async function deliver(ref: FirebaseFirestore.DocumentReference): Promise<boolean> {
  const b = (await ref.get()).data() as any;
  if ((b.replierIds ?? []).length >= MAX_REPLIERS) { await ref.update({ deliveryState: "done", recipientId: null }); return false; }
  const sender = await db.doc(`users/${b.senderId}`).get();
  if (!sender.exists) return false;
  const exclude = [b.senderId, ...(b.thrownBackBy ?? []), ...(b.replierIds ?? [])];
  const cands = await eligibleUsers({ id: sender.id, ...sender.data() }, exclude);
  if (cands.length === 0) { await ref.update({ deliveryState: "floating", recipientId: null, updatedAt: new Date() }); return false; }
  const loads = await Promise.all(cands.slice(0, 30).map(async (c) =>
    (await db.collection("bottles").where("recipientId", "==", c.id).where("deliveryState", "==", "delivered").count().get()).data().count));
  let best = 0; loads.forEach((l, i) => { if (l < loads[best]) best = i; });
  await ref.update({ deliveryState: "delivered", recipientId: cands[best].id, updatedAt: new Date() });
  return true;
}

// ---------------- 设备 / 用户（匿名登录，无需注册）----------------
const NICK = (loc: string) => t(loc, "nickname.format", Math.floor(1000 + Math.random() * 9000));
const cnYear = () => new Date(Date.now() + 8 * 3600e3).getUTCFullYear();

/** 完成引导：只填性别 + 年龄（18+），昵称可选；性别/年龄此后不可修改 */
export const createProfile = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const loc = locOf(req);
  const gender = req.data?.gender; const age = Number(req.data?.age);
  const deviceId = String(req.data?.deviceId ?? "").slice(0, 64);
  if (gender !== "male" && gender !== "female") return { error: t(loc, "err.gender") };
  if (!Number.isInteger(age) || age < 18 || age > 80) return { error: t(loc, "onb.age_min") };
  let nickname = String(req.data?.nickname ?? "").trim();
  if (!nickname || nickname.length > 12 || !moderateTextLocal(nickname).ok) nickname = NICK(loc);
  if (deviceId && (await db.doc(`bannedDevices/${deviceId}`).get()).exists) return { error: t(loc, "err.device_banned") };

  const userRef = db.doc(`users/${uid}`);
  const devRef = deviceId ? db.doc(`devices/${deviceId}`) : null;
  return db.runTransaction(async (tx) => {
    if ((await tx.get(userRef)).exists) return { error: t(loc, "err.profile_exists") };
    // 新账号窗口从“设备首次使用时间”起算，卸载重装不会重置
    let firstSeen = new Date();
    if (devRef) {
      const dev = await tx.get(devRef);
      const fs = toDate(dev.data()?.firstSeenAt);
      if (fs) firstSeen = fs;
      tx.set(devRef, { firstSeenAt: firstSeen, uids: FV.arrayUnion(uid), updatedAt: new Date() }, { merge: true });
    }
    tx.set(userRef, {
      nickname, gender, age, birthYear: cnYear() - age, ageSetAt: FV.serverTimestamp(),
      isMember: false, memberTier: "free", blockedUserIds: [], deviceId: deviceId || null, banned: false, locale: loc,
      serverCreatedAt: firstSeen, createdAt: new Date(),
    });
    return { ok: true, nickname };
  });
});

export const getQuota = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const u = await getUser(uid);
  const q = (await quotaRef(u).get()).data() ?? {};
  return { throws: q.throws ?? 0, picks: q.picks ?? 0, throwLimit: dailyLimit(u, "throws"), pickLimit: dailyLimit(u, "picks"), tier: tierOf(u), unlimited: isUnlimited(tierOf(u)) };
});

export const registerDevice = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const deviceId = String(req.data?.deviceId ?? "").slice(0, 64);
  if (!deviceId) return { ok: false };
  if ((await db.doc(`bannedDevices/${deviceId}`).get()).exists) {
    await db.doc(`users/${uid}`).update({ banned: true }).catch(() => undefined);
    return { ok: false, banned: true };
  }
  // 只在资料已存在且尚未绑定设备时写入，避免换设备 ID 绕过新账号限制
  const u = await db.doc(`users/${uid}`).get();
  if (u.exists && !u.data()!.deviceId) await u.ref.update({ deviceId });
  const devRef = db.doc(`devices/${deviceId}`);
  await db.runTransaction(async (t) => {
    const d = await t.get(devRef);
    t.set(devRef, { uids: FV.arrayUnion(uid), updatedAt: new Date(), ...(d.data()?.firstSeenAt ? {} : { firstSeenAt: new Date() }) }, { merge: true });
  });
  return { ok: true };
});

/** 新用户完成资料（由 createProfile 写入）：把漂流中、符合条件的瓶子分配给 TA */
export const onUserCreated = onDocumentCreated({ document: "users/{uid}", region: REGION }, async (e) => {
  const uid = e.params.uid; const u: any = { id: uid, ...e.data?.data() };
  const floating = await db.collection("bottles").where("deliveryState", "==", "floating")
    .where("senderGender", "==", opposite(u.gender))
    .where("senderBirthYear", ">=", u.birthYear - AGE).where("senderBirthYear", "<=", u.birthYear + AGE).limit(50).get();
  const docs = floating.docs.filter((d) => !(d.data().thrownBackBy ?? []).includes(uid))
    .sort((a, b) => (a.data().pickCount - b.data().pickCount) || (toDate(a.data().createdAt)!.getTime() - toDate(b.data().createdAt)!.getTime()))
    .slice(0, 10);
  for (const d of docs) {
    const sender = await db.doc(`users/${d.data().senderId}`).get();
    if (!sender.exists || !mutuallyOk({ id: sender.id, ...sender.data() }, u)) continue;
    await d.ref.update({ deliveryState: "delivered", recipientId: uid, updatedAt: new Date() });
    if (d.data().status === "aiReplied") await notify(d.data().senderId, d.id, "notice.real_arrived", "system");
  }
});

export const blockUser = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const target = String(req.data?.targetUserId ?? ""); if (!target || target === AI_ID) return { ok: false };
  await db.doc(`users/${uid}`).update({ blockedUserIds: FV.arrayUnion(target) });
  const chatId = req.data?.chatId as string | undefined;
  if (chatId) {
    const c = await db.doc(`chats/${chatId}`).get();
    if (c.exists && (c.data()!.participants as string[]).includes(uid)) await c.ref.update({ blocked: true });
  }
  return { ok: true };
});

/** 举报被管理员确认（reports/{id}.status 改为 confirmed）→ 封禁账号与设备 */
export const onReportConfirmed = onDocumentUpdated({ document: "reports/{id}", region: REGION }, async (e) => {
  const before = e.data?.before.data(), after = e.data?.after.data();
  if (!after || before?.status === "confirmed" || after.status !== "confirmed") return;
  const target = await db.doc(`users/${after.targetUserId}`).get();
  if (!target.exists) return;
  await target.ref.update({ banned: true });
  const deviceId = target.data()!.deviceId;
  if (deviceId) await db.doc(`bannedDevices/${deviceId}`).set({ uid: target.id, reportId: e.params.id, createdAt: new Date() });
  const pending = await db.collection("bottles").where("senderId", "==", target.id).where("deliveryState", "in", ["floating", "delivered"]).get();
  await Promise.all(pending.docs.map((d) => d.ref.update({ deliveryState: "done", recipientId: null })));
});

// ---------------- 瓶子 ----------------
export const throwBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  let loc = locOf(req);
  const text = String(req.data?.text ?? "").trim();
  const imagePath = typeof req.data?.imagePath === "string" ? req.data.imagePath : null;
  const imageURL = imagePath && typeof req.data?.imageURL === "string" ? req.data.imageURL : null;
  if (imagePath && (!imagePath.startsWith(`bottles/${uid}/`) || imagePath.includes(".."))) return { error: t(loc, "err.image_path") };
  const style = typeof req.data?.style === "string" ? req.data.style : "classic";
  // 无最少字数：至少 1 个非空白字符（已 trim），最多 200 字
  if (!text || charCount(text) > MAX_BOTTLE) return { error: t(loc, "err.bottle_len", MAX_BOTTLE) };
  const mod = await moderate(text, imageURL);
  if (!mod.ok) return { error: t(loc, "err.mod", reason(loc, mod.reason)) };
  const user = await getUser(uid, loc); loc = locOf(req, user);
  if (EXCLUSIVE_STYLES.includes(style) && tierOf(user) !== "annual") return { error: t(loc, "err.style_exclusive") };
  if (!(await consumeQuota(user, "throws"))) return { error: isUnlimited(tierOf(user)) && dailyLimit(user, "throws") > 3 ? t(loc, "home.too_frequent") : t(loc, "err.throws_used", dailyLimit(user, "throws")) };

  // 图片审核：Storage 触发器可能已先完成审核
  let imageStatus: "none" | "pending" | "approved" = "none";
  if (imagePath) {
    const r = (await db.doc(`imageReviews/${reviewId(imagePath)}`).get()).data();
    if (r && r.ok === false) return { error: t(loc, "err.img_mod", reason(loc, r.reason ?? "mod.community")) };
    imageStatus = r ? "approved" : "pending";
  }
  const ref = await db.collection("bottles").add({
    imagePath, imageStatus,
    senderId: uid, senderNickname: user.nickname, senderGender: user.gender, senderBirthYear: user.birthYear,
    text, imageURL, style: EXCLUSIVE_STYLES.includes(style) ? style : "classic", status: "floating", deliveryState: imageStatus === "pending" ? "pendingImage" : "floating", recipientId: null,
    pickCount: 0, thrownBackBy: [], replierIds: [], createdAt: new Date(), updatedAt: new Date(),
  });
  await db.doc(`users/${uid}`).update({ "stats.thrown": FV.increment(1), "stats.lastActiveAt": new Date() });
  if (imageStatus === "pending") {
    // 防竞态：审核恰好在创建瓶子前后完成
    const r = (await db.doc(`imageReviews/${reviewId(imagePath!)}`).get()).data();
    if (r) { await applyImageVerdict(ref, (await ref.get()).data(), r.ok !== false, r.reason ?? undefined);
      if (r.ok === false) return { error: t(loc, "err.img_mod", reason(loc, r.reason ?? "mod.community")) };
      return { message: t(loc, "msg.sent_real"), bottleId: ref.id }; }
  }
  if (imageStatus === "pending") return { message: t(loc, "msg.img_pending"), bottleId: ref.id, pendingImage: true };
  return { ...(await launch(ref, uid, text, loc)), bottleId: ref.id };
});

/** 让瓶子出发：投递给真人；这片海只有一位用户时由灯塔守望者（AI）回复 */
async function launch(ref: FirebaseFirestore.DocumentReference, uid: string, text: string, locale?: string): Promise<{ message: string; ai?: boolean }> {
  const loc = locale ?? (await db.doc(`users/${uid}`).get()).data()?.locale;
  if (await deliver(ref)) return { message: t(loc, "msg.sent_real") };
  const others = await db.collection("users").where(admin.firestore.FieldPath.documentId(), "!=", uid).limit(1).get();
  if (others.empty) {
    const reply = aiReply(text, loc);
    const chat = await db.collection("chats").add({ participants: [uid, AI_ID], bottleId: ref.id, isAI: true, blocked: false,
      names: { [AI_ID]: t(loc, "push.ai") }, lastMessage: reply, updatedAt: new Date() });
    await chat.collection("messages").add({ senderId: AI_ID, text: reply, isAI: true, createdAt: new Date() });
    await ref.update({ status: "aiReplied", chatId: chat.id });
    await notify(uid, ref.id, "ai.first_visitor", "ai");
    return { message: t(loc, "ai.first_visitor"), ai: true };
  }
  return { message: t(loc, "msg.no_one") };
}

// ---------------- 图片审核（Storage 触发，Cloud Vision SafeSearch）----------------
/** 上传到 bottles/{uid}/ 的图片：审核结果写入 imageReviews；拦截则删除图片、隐藏瓶子；通过则放行瓶子 */
export const onBottleImageUploaded = onObjectFinalized({ region: REGION, memory: "512MiB" }, async (e) => {
  const path = e.data.name; if (!path?.startsWith("bottles/")) return;
  let verdict: { ok: boolean; reason?: string; scores?: Record<string, string> };
  try { verdict = await checkImage(`gs://${e.data.bucket}/${path}`); }
  catch (err) { logger.error("Vision 审核失败，按宽松策略放行", { path, err: String(err) }); verdict = { ok: true, reason: "vision_error" }; }
  await db.doc(`imageReviews/${reviewId(path)}`).set({ path, ok: verdict.ok, reason: verdict.reason ?? null, scores: verdict.scores ?? null, reviewedAt: new Date() });
  if (!verdict.ok) await admin.storage().bucket(e.data.bucket).file(path).delete().catch(() => undefined);
  const bottles = await db.collection("bottles").where("imagePath", "==", path).limit(5).get();
  for (const d of bottles.docs) await applyImageVerdict(d.ref, d.data(), verdict.ok, verdict.reason);
});

async function applyImageVerdict(ref: FirebaseFirestore.DocumentReference, b: any, ok: boolean, why?: string) {
  if (b.imageStatus !== "pending") return;
  if (ok) {
    await ref.update({ imageStatus: "approved", deliveryState: "floating", updatedAt: new Date() });
    await launch(ref, b.senderId, b.text);
  } else {
    await ref.update({ imageStatus: "blocked", hidden: true, imageURL: null, deliveryState: "done", status: "floating", updatedAt: new Date() });
    const loc = (await db.doc(`users/${b.senderId}`).get()).data()?.locale;
    await notify(b.senderId, ref.id, "notice.img_blocked", "system", "imageBlocked", reason(loc, why ?? "mod.community"));
  }
}


export const pickBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const user = await getUser(uid, req.data?.locale);
  const loc = locOf(req, user);
  let snap = await db.collection("bottles").where("recipientId", "==", uid).where("deliveryState", "==", "delivered")
    .orderBy("pickCount").orderBy("createdAt").limit(1).get();
  if (snap.empty) {
    const floating = await db.collection("bottles").where("deliveryState", "==", "floating")
      .where("senderGender", "==", opposite(user.gender))
      .where("senderBirthYear", ">=", user.birthYear - AGE).where("senderBirthYear", "<=", user.birthYear + AGE).limit(30).get();
    const ok = floating.docs.filter((d) => {
      const b = d.data(); return b.senderId !== uid && !(b.thrownBackBy ?? []).includes(uid) && !(b.replierIds ?? []).includes(uid)
        && !(user.blockedUserIds ?? []).includes(b.senderId);
    }).sort((a, b) => a.data().pickCount - b.data().pickCount);
    if (ok.length) snap = { empty: false, docs: [ok[0]] } as any;
  }
  if (snap.empty) {
    const others = await db.collection("users").where(admin.firestore.FieldPath.documentId(), "!=", uid).limit(1).get();
    if (others.empty) return { firstVisitor: true };
    return { message: t(loc, "msg.no_bottle") };
  }
  if (!(await consumeQuota(user, "picks"))) return { error: t(loc, "err.picks_used") };
  const doc = snap.docs[0];
  await db.doc(`users/${uid}`).update({ "stats.picked": FV.increment(1), "stats.lastActiveAt": new Date() });
  await doc.ref.update({ status: "viewed", deliveryState: "held", recipientId: uid, viewedAt: new Date(), pickCount: FV.increment(1), updatedAt: new Date() });
  await notify(doc.data().senderId, doc.id, "notice.picked", "human");
  return { bottleId: doc.id };
});

async function heldBy(uid: string, bottleId: string, loc?: string) {
  const ref = db.doc(`bottles/${bottleId}`);
  const b = (await ref.get()).data();
  if (!b || b.recipientId !== uid || b.deliveryState !== "held") throw new HttpsError("permission-denied", t(loc, "err.gone"));
  return { ref, b };
}

export const keepBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const { ref, b } = await heldBy(uid, req.data?.bottleId, locOf(req));
  if ((b.replierIds ?? []).length >= MAX_REPLIERS) return { error: t(locOf(req), "err.full", MAX_REPLIERS) };
  await ref.update({ status: "kept", updatedAt: new Date() });
  await notify(b.senderId, ref.id, "notice.kept", "human");
  return { ok: true };
});

export const releaseBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const { ref, b } = await heldBy(uid, req.data?.bottleId, locOf(req));
  await ref.update({ status: (b.replierIds ?? []).length ? "replied" : "thrownBack", thrownBackBy: FV.arrayUnion(uid), updatedAt: new Date() });
  await notify(b.senderId, ref.id, "notice.thrown", "human");
  await deliver(ref);
  return { ok: true };
});

export const replyBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  let loc = locOf(req);
  const text = String(req.data?.text ?? "").trim();
  if (!text || charCount(text) > MAX_REPLY) return { error: t(loc, "err.reply_len", MAX_REPLY) };
  const mod = await moderate(text); if (!mod.ok) return { error: t(loc, "err.mod", reason(loc, mod.reason)) };
  const me = await getUser(uid, loc); loc = locOf(req, me);
  const { ref, b } = await heldBy(uid, req.data?.bottleId, loc);
  if (b.status !== "kept") return { error: t(loc, "err.keep_first") };
  const replierIds: string[] = b.replierIds ?? [];
  if (replierIds.length >= MAX_REPLIERS) return { error: t(loc, "err.full", MAX_REPLIERS) };
  const chat = await db.collection("chats").add({ participants: [b.senderId, uid], bottleId: ref.id, isAI: false, blocked: false,
    names: { [b.senderId]: b.senderNickname, [uid]: me.nickname }, lastMessage: text, updatedAt: new Date() });
  await chat.collection("messages").add({ senderId: b.senderId, text: b.text, kind: "origin", imageURL: b.imageURL ?? null, isAI: false, createdAt: toDate(b.createdAt) ?? new Date() });
  await chat.collection("messages").add({ senderId: uid, text, isAI: false, createdAt: new Date() });
  const n = replierIds.length + 1;
  await ref.update({ status: "replied", chatId: chat.id, replierIds: FV.arrayUnion(uid), thrownBackBy: FV.arrayUnion(uid), updatedAt: new Date() });
  await notify(b.senderId, ref.id, "notice.replied", "human", "replied", n, MAX_REPLIERS);
  await deliver(ref); // 未满 3 人继续漂流
  return { chatId: chat.id };
});

/** 每小时：捡起超过 24 小时未回复 → viewedNoReply 并继续漂流 */
export const markViewedNoReply = onSchedule({ schedule: "every 60 minutes", region: REGION }, async () => {
  const cutoff = new Date(Date.now() - NO_REPLY_HOURS * 3600e3);
  const snap = await db.collection("bottles").where("deliveryState", "==", "held").where("viewedAt", "<=", cutoff).get();
  for (const d of snap.docs) {
    const b = d.data();
    await d.ref.update({ status: (b.replierIds ?? []).length ? "replied" : "viewedNoReply", thrownBackBy: FV.arrayUnion(b.recipientId), updatedAt: new Date() });
    await notify(b.senderId, d.id, "notice.viewed_no_reply", "human");
    await deliver(d.ref);
  }
});

// ---------------- 聊天 ----------------
/** 新消息：服务端审核 + 更新会话；AI 会话由灯塔守望者回复 */
export const onMessageCreated = onDocumentCreated({ document: "chats/{chatId}/messages/{msgId}", region: REGION }, async (e) => {
  const m = e.data?.data(); if (!m || m.isAI || m.kind === "origin") return; // 瓶子原文已在投递时审核，不更新 lastMessage、不推送
  const chatRef = db.doc(`chats/${e.params.chatId}`);
  const chat = (await chatRef.get()).data(); if (!chat) return;
  const check = moderateTextLocal(m.text ?? "");
  if (!check.ok) { await e.data!.ref.update({ text: "", imageURL: null, hidden: true }); return; } // 客户端按 hidden 显示本地化提示
  await chatRef.update({ lastMessage: m.text || "", updatedAt: new Date() }); // 空 = 图片，客户端本地化
  if (chat.isAI && m.senderId !== AI_ID) {
    const owner = (chat.participants as string[]).find((p) => p !== AI_ID);
    const reply = aiReply(m.text ?? "", owner ? (await db.doc(`users/${owner}`).get()).data()?.locale : undefined);
    await chatRef.collection("messages").add({ senderId: AI_ID, text: reply, isAI: true, createdAt: new Date() });
    await chatRef.update({ lastMessage: reply, updatedAt: new Date() });
  } else {
    const other = (chat.participants as string[]).find((p) => p !== m.senderId);
    const oloc = other ? (await db.doc(`users/${other}`).get()).data()?.locale : undefined;
    if (other && !chat.blocked) await sendPush(other, { title: chat.names?.[m.senderId] ?? t(oloc, "push.new_msg"),
      body: m.text ? (m.text.length > 40 ? m.text.slice(0, 40) + "…" : m.text) : t(oloc, "chat.image"), key: `chat_${e.params.chatId}`, gapMs: CHAT_GAP,
      data: { chatId: e.params.chatId, event: "message" } });
  }
});

// ---------------- 会员 ----------------
export const syncMembership = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const jws = String(req.data?.signedTransaction ?? "");
  if (!jws) return { isMember: false, tier: "free" };
  try {
    const info = await verifyTransaction(jws);
    // 防止一笔订阅被多个账号共用
    if (info.originalTransactionId) {
      const owner = db.doc(`subscriptions/${info.originalTransactionId}`);
      const o = await owner.get();
      if (o.exists && o.data()!.uid !== uid) return { isMember: false, error: t(locOf(req), "err.sub_bound") };
      await owner.set({ uid, expiresAt: info.expiresAt, updatedAt: new Date() }, { merge: true });
    }
    // 等级由商品 ID 映射（PRODUCTS → TIER_QUOTA），客户端无法写入
    await db.doc(`users/${uid}`).update({ isMember: info.isMember, memberTier: info.tier, memberExpiresAt: info.expiresAt });
    return { isMember: info.isMember, tier: info.tier, unlimited: isUnlimited(info.tier), expiresAt: info.expiresAt?.toISOString() ?? null };
  } catch (err: any) {
    throw new HttpsError("invalid-argument", t(locOf(req), "err.tx", String(err?.message ?? err)));
  }
});

export const deleteAccount = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const bottles = await db.collection("bottles").where("senderId", "==", uid).get();
  const batch = db.batch(); bottles.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  const chats = await db.collection("chats").where("participants", "array-contains", uid).get();
  await Promise.all(chats.docs.map((c) => c.ref.update({ blocked: true, [`names.${uid}`]: FV.delete() }))); // 客户端显示本地化“匿名旅人”
  await db.recursiveDelete(db.doc(`users/${uid}`)); // devices / bannedDevices / deviceQuota 保留，重装不会重置限制
  await admin.auth().deleteUser(uid).catch(() => undefined); // 删除匿名账号
  await admin.storage().bucket().deleteFiles({ prefix: `bottles/${uid}/` }).catch(() => undefined);
  return { ok: true };
});

/** AI 回复 stub：接入大模型时必须保持“灯塔守望者（AI）”身份（各语言名称见 ai.name），用用户语言回复，绝不冒充真实用户 */
function aiReply(text: string, locale?: string): string {
  const q = text.slice(0, 30) + (text.length > 30 ? "…" : "");
  return t(locale, "ai.reply", q);
}

export { appStoreNotifications } from "./storeNotifications";

/** 用户在付费页/条款中同意向 Apple 共享使用数据（用于处理退款请求） */
export const setConsumptionConsent = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  await db.doc(`users/${uid}`).update({ consumptionConsent: req.data?.consent === true, consumptionConsentAt: new Date() });
  return { ok: true };
});

// ---------------- 管理（需 admin 自定义声明）----------------
/** 新举报：标记为 pending，便于管理员按时间查看 */
export const onReportCreated = onDocumentCreated({ document: "reports/{id}", region: REGION }, async (e) => {
  await e.data?.ref.update({ status: "pending", createdAt: e.data.data().createdAt ?? new Date() });
});

/** 处理举报：action = "ban"（封禁账号+设备，触发 onReportConfirmed）| "dismiss"（驳回） */
export const reviewReport = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  if (req.auth?.token?.admin !== true) throw new HttpsError("permission-denied", "仅管理员可操作");
  const reportId = String(req.data?.reportId ?? ""); const action = req.data?.action;
  if (!reportId || (action !== "ban" && action !== "dismiss")) throw new HttpsError("invalid-argument", "参数错误");
  const ref = db.doc(`reports/${reportId}`);
  const r = await ref.get(); if (!r.exists) throw new HttpsError("not-found", "举报不存在");
  if (r.data()!.status === "confirmed" || r.data()!.status === "dismissed") return { ok: true, already: r.data()!.status };
  await ref.update({ status: action === "ban" ? "confirmed" : "dismissed", reviewedBy: uid, reviewedAt: new Date(), note: String(req.data?.note ?? "").slice(0, 200) });
  return { ok: true };
});
