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
import * as admin from "firebase-admin";
import { moderate, moderateTextLocal } from "./moderation";
import { verifyTransaction, TIER_QUOTA, EXCLUSIVE_STYLES, isUnlimited, Tier } from "./appstore";

admin.initializeApp();
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const REGION = "asia-east2";
const NEW_ACCOUNT_THROWS = 3, AGE = 10, NO_REPLY_HOURS = 24, MAX_REPLIERS = 3;
const AI_ID = "ai_lighthouse";
const FIRST_VISITOR = "你是这片海的第一位访客，灯塔守望者先陪你聊聊";

type Kind = "human" | "ai" | "system";
const dayKey = () => new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10).replace(/-/g, "");
const opposite = (g: string) => (g === "male" ? "female" : "male");
const toDate = (v: any): Date | null => (v?.toDate ? v.toDate() : v instanceof Date ? v : null);

function requireUid(req: CallableRequest): string {
  const uid = req.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", "请先登录");
  return uid;
}

async function getUser(uid: string) {
  const d = await db.doc(`users/${uid}`).get();
  if (!d.exists) throw new HttpsError("failed-precondition", "请先完善资料");
  const u: any = { id: uid, ...d.data() };
  if (u.banned) throw new HttpsError("permission-denied", "账号因违规已被限制使用");
  if (u.deviceId && (await db.doc(`bannedDevices/${u.deviceId}`).get()).exists) throw new HttpsError("permission-denied", "该设备因违规已被限制使用");
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

async function notify(uid: string, bottleId: string, message: string, kind: Kind, event = "status") {
  await db.collection(`users/${uid}/notices`).add({ bottleId, message, kind, event, read: false, createdAt: new Date() });
  const token = (await db.doc(`users/${uid}`).get()).data()?.fcmToken;
  if (token) {
    // 推送 stub：上传 APNs Key 后生效
    await admin.messaging().send({ token, notification: { title: kind === "ai" ? "灯塔守望者（AI）" : "漂流瓶", body: message } }).catch(() => undefined);
  }
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
const NICK = () => "漂流者" + String(Math.floor(Math.random() * 10000)).padStart(4, "0");
const cnYear = () => new Date(Date.now() + 8 * 3600e3).getUTCFullYear();

/** 完成引导：只填性别 + 年龄（18+），昵称可选；性别/年龄此后不可修改 */
export const createProfile = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const gender = req.data?.gender; const age = Number(req.data?.age);
  const deviceId = String(req.data?.deviceId ?? "").slice(0, 64);
  if (gender !== "male" && gender !== "female") return { error: "请选择性别" };
  if (!Number.isInteger(age) || age < 18 || age > 80) return { error: "仅限 18 岁及以上使用" };
  let nickname = String(req.data?.nickname ?? "").trim();
  if (!nickname || nickname.length > 12 || !moderateTextLocal(nickname).ok) nickname = NICK();
  if (deviceId && (await db.doc(`bannedDevices/${deviceId}`).get()).exists) return { error: "该设备因违规已被限制使用" };

  const userRef = db.doc(`users/${uid}`);
  const devRef = deviceId ? db.doc(`devices/${deviceId}`) : null;
  return db.runTransaction(async (t) => {
    if ((await t.get(userRef)).exists) return { error: "资料已创建，性别和年龄不可修改" };
    // 新账号窗口从“设备首次使用时间”起算，卸载重装不会重置
    let firstSeen = new Date();
    if (devRef) {
      const dev = await t.get(devRef);
      const fs = toDate(dev.data()?.firstSeenAt);
      if (fs) firstSeen = fs;
      t.set(devRef, { firstSeenAt: firstSeen, uids: FV.arrayUnion(uid), updatedAt: new Date() }, { merge: true });
    }
    t.set(userRef, {
      nickname, gender, age, birthYear: cnYear() - age, ageSetAt: FV.serverTimestamp(),
      isMember: false, memberTier: "free", blockedUserIds: [], deviceId: deviceId || null, banned: false,
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
    if (d.data().status === "aiReplied") await notify(d.data().senderId, d.id, "一位真实的旅人来到了这片海，你的瓶子正漂向 TA", "system");
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
  const text = String(req.data?.text ?? "").trim();
  const imageURL = typeof req.data?.imageURL === "string" ? req.data.imageURL : null;
  const style = typeof req.data?.style === "string" ? req.data.style : "classic";
  if (!text || text.length > 200) return { error: "瓶子内容需在 1–200 字之间" };
  const mod = await moderate(text, imageURL);
  if (!mod.ok) return { error: `内容未通过审核：${mod.reason}` };
  const user = await getUser(uid);
  if (EXCLUSIVE_STYLES.includes(style) && tierOf(user) !== "annual") return { error: "这款瓶子样式是年卡专属" };
  if (!(await consumeQuota(user, "throws"))) return { error: isUnlimited(tierOf(user)) && dailyLimit(user, "throws") > 3 ? "今天扔得太频繁了，休息一下，明天再来吧" : `今天的扔瓶次数用完了（${dailyLimit(user, "throws")} 次）` };

  const ref = await db.collection("bottles").add({
    senderId: uid, senderNickname: user.nickname, senderGender: user.gender, senderBirthYear: user.birthYear,
    text, imageURL, style: EXCLUSIVE_STYLES.includes(style) ? style : "classic", status: "floating", deliveryState: "floating", recipientId: null,
    pickCount: 0, thrownBackBy: [], replierIds: [], createdAt: new Date(), updatedAt: new Date(),
  });
  if (await deliver(ref)) return { message: "瓶子已经漂向大海，很快会被一位真实的旅人捡到", bottleId: ref.id };

  const others = await db.collection("users").where(admin.firestore.FieldPath.documentId(), "!=", uid).limit(1).get();
  if (others.empty) {
    // 只有第一位用户时，灯塔守望者（AI）回复并告知
    const reply = await aiReply(text);
    const chat = await db.collection("chats").add({ participants: [uid, AI_ID], bottleId: ref.id, isAI: true, blocked: false,
      names: { [AI_ID]: "灯塔守望者（AI）" }, lastMessage: reply, updatedAt: new Date() });
    await chat.collection("messages").add({ senderId: AI_ID, text: reply, isAI: true, createdAt: new Date() });
    await ref.update({ status: "aiReplied", chatId: chat.id });
    await notify(uid, ref.id, FIRST_VISITOR, "ai");
    return { message: FIRST_VISITOR, bottleId: ref.id, ai: true };
  }
  return { message: "附近暂时没有合适的旅人，瓶子会一直漂流，直到有人出现", bottleId: ref.id };
});

export const pickBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const user = await getUser(uid);
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
    return { message: "海面上暂时没有漂到你身边的瓶子，过会儿再来看看吧" };
  }
  if (!(await consumeQuota(user, "picks"))) return { error: "今天的捡瓶次数用完了" };
  const doc = snap.docs[0];
  await doc.ref.update({ status: "viewed", deliveryState: "held", recipientId: uid, viewedAt: new Date(), pickCount: FV.increment(1), updatedAt: new Date() });
  await notify(doc.data().senderId, doc.id, "一位真实的旅人捡起了你的瓶子，正在阅读", "human");
  return { bottleId: doc.id };
});

async function heldBy(uid: string, bottleId: string) {
  const ref = db.doc(`bottles/${bottleId}`);
  const b = (await ref.get()).data();
  if (!b || b.recipientId !== uid || b.deliveryState !== "held") throw new HttpsError("permission-denied", "这个瓶子已经漂走了");
  return { ref, b };
}

export const keepBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const { ref, b } = await heldBy(uid, req.data?.bottleId);
  if ((b.replierIds ?? []).length >= MAX_REPLIERS) return { error: "这个瓶子已经有 3 人回复了，放它走吧" };
  await ref.update({ status: "kept", updatedAt: new Date() });
  await notify(b.senderId, ref.id, "一位真实的旅人保留了你的瓶子，正在写回信", "human");
  return { ok: true };
});

export const releaseBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const { ref, b } = await heldBy(uid, req.data?.bottleId);
  await ref.update({ status: (b.replierIds ?? []).length ? "replied" : "thrownBack", thrownBackBy: FV.arrayUnion(uid), updatedAt: new Date() });
  await notify(b.senderId, ref.id, "你的瓶子被一位真实的旅人捡起来看了，又被扔回了大海", "human");
  await deliver(ref);
  return { ok: true };
});

export const replyBottle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const text = String(req.data?.text ?? "").trim();
  if (!text || text.length > 500) return { error: "回复需在 1–500 字之间" };
  const mod = await moderate(text); if (!mod.ok) return { error: `内容未通过审核：${mod.reason}` };
  const me = await getUser(uid);
  const { ref, b } = await heldBy(uid, req.data?.bottleId);
  if (b.status !== "kept") return { error: "请先保留这个瓶子再回复" };
  const replierIds: string[] = b.replierIds ?? [];
  if (replierIds.length >= MAX_REPLIERS) return { error: "这个瓶子已经有 3 人回复了" };
  const chat = await db.collection("chats").add({ participants: [b.senderId, uid], bottleId: ref.id, isAI: false, blocked: false,
    names: { [b.senderId]: b.senderNickname, [uid]: me.nickname }, lastMessage: text, updatedAt: new Date() });
  await chat.collection("messages").add({ senderId: b.senderId, text: `【瓶子】${b.text}`, imageURL: b.imageURL ?? null, isAI: false, createdAt: toDate(b.createdAt) ?? new Date() });
  await chat.collection("messages").add({ senderId: uid, text, isAI: false, createdAt: new Date() });
  const n = replierIds.length + 1;
  await ref.update({ status: "replied", chatId: chat.id, replierIds: FV.arrayUnion(uid), thrownBackBy: FV.arrayUnion(uid), updatedAt: new Date() });
  await notify(b.senderId, ref.id, `一位真实的旅人回复了你的瓶子（${n}/${MAX_REPLIERS}），快去聊聊吧`, "human", "replied");
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
    await notify(b.senderId, d.id, "有人看了你的瓶子，但还没有回应", "human");
    await deliver(d.ref);
  }
});

// ---------------- 聊天 ----------------
/** 新消息：服务端审核 + 更新会话；AI 会话由灯塔守望者回复 */
export const onMessageCreated = onDocumentCreated({ document: "chats/{chatId}/messages/{msgId}", region: REGION }, async (e) => {
  const m = e.data?.data(); if (!m || m.isAI) return;
  const chatRef = db.doc(`chats/${e.params.chatId}`);
  const chat = (await chatRef.get()).data(); if (!chat) return;
  const check = moderateTextLocal(m.text ?? "");
  if (!check.ok) { await e.data!.ref.update({ text: "（该消息因违反社区规范已被隐藏）", imageURL: null, hidden: true }); return; }
  await chatRef.update({ lastMessage: m.text || "[图片]", updatedAt: new Date() });
  if (chat.isAI && m.senderId !== AI_ID) {
    const reply = await aiReply(m.text ?? "");
    await chatRef.collection("messages").add({ senderId: AI_ID, text: reply, isAI: true, createdAt: new Date() });
    await chatRef.update({ lastMessage: reply, updatedAt: new Date() });
  } else {
    const other = (chat.participants as string[]).find((p) => p !== m.senderId);
    const token = other ? (await db.doc(`users/${other}`).get()).data()?.fcmToken : null;
    if (token) await admin.messaging().send({ token, notification: { title: chat.names?.[m.senderId] ?? "新消息", body: m.text || "[图片]" } }).catch(() => undefined);
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
      if (o.exists && o.data()!.uid !== uid) return { isMember: false, error: "该订阅已绑定其他账号" };
      await owner.set({ uid, expiresAt: info.expiresAt, updatedAt: new Date() }, { merge: true });
    }
    // 等级由商品 ID 映射（PRODUCTS → TIER_QUOTA），客户端无法写入
    await db.doc(`users/${uid}`).update({ isMember: info.isMember, memberTier: info.tier, memberExpiresAt: info.expiresAt });
    return { isMember: info.isMember, tier: info.tier, unlimited: isUnlimited(info.tier), expiresAt: info.expiresAt?.toISOString() ?? null };
  } catch (err: any) {
    throw new HttpsError("invalid-argument", `交易校验失败：${err?.message ?? err}`);
  }
});

export const deleteAccount = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req);
  const bottles = await db.collection("bottles").where("senderId", "==", uid).get();
  const batch = db.batch(); bottles.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  const chats = await db.collection("chats").where("participants", "array-contains", uid).get();
  await Promise.all(chats.docs.map((c) => c.ref.update({ blocked: true, [`names.${uid}`]: "已注销用户" })));
  await db.recursiveDelete(db.doc(`users/${uid}`)); // devices / bannedDevices / deviceQuota 保留，重装不会重置限制
  await admin.auth().deleteUser(uid).catch(() => undefined); // 删除匿名账号
  await admin.storage().bucket().deleteFiles({ prefix: `bottles/${uid}/` }).catch(() => undefined);
  return { ok: true };
});

/** AI 回复 stub：接入大模型时必须保持“灯塔守望者（AI）”身份，绝不冒充真实用户 */
async function aiReply(text: string): Promise<string> {
  const t = text.slice(0, 30) + (text.length > 30 ? "…" : "");
  return `【灯塔守望者 · AI】我收到了你的话：“${t}”。我是 AI，不是真人。${FIRST_VISITOR}，等其他旅人来了，你的瓶子会第一时间漂向他们。`;
}
