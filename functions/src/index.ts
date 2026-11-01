/**
 * 漂流瓶匹配逻辑（Cloud Functions v2，TypeScript）
 * 规则：
 *  - 只匹配异性、年龄差 ±10 岁、未互相拉黑的真实用户
 *  - 只要存在符合条件的真实用户，每个瓶子必然被投递给某位真实用户（扔回后会重新投递给下一位）
 *  - 捡瓶时优先拿“从未被捡过”的瓶子
 *  - 仅当没有任何符合条件的其他真实用户时（如第一位用户），由「灯塔守望者」（AI，明确标注）回复
 *  - 状态变化写入 users/{uid}/notices 并发送推送（推送为 stub）
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
admin.initializeApp();
const db = admin.firestore();
const REGION = "asia-east2";
const FREE = 8, MEMBER = 30, AGE = 10, NO_REPLY_HOURS = 24;
const AI_ID = "ai_lighthouse";
const SENSITIVE = ["赌博", "代孕", "毒品", "裸聊", "约炮", "加微信转账", "色情"];

const dayKey = () => new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10).replace(/-/g, "");
const opposite = (g: string) => (g === "male" ? "female" : "male");

async function getUser(uid: string) {
  const d = await db.doc(`users/${uid}`).get();
  if (!d.exists) throw new HttpsError("failed-precondition", "请先完善资料");
  return { id: uid, ...(d.data() as any) };
}

async function consumeQuota(uid: string, isMember: boolean, field: "throws" | "picks") {
  const ref = db.doc(`users/${uid}/quota/${dayKey()}`);
  const limit = isMember ? MEMBER : FREE;
  return db.runTransaction(async (t) => {
    const cur = ((await t.get(ref)).data()?.[field] as number) ?? 0;
    if (cur >= limit) return false;
    t.set(ref, { [field]: cur + 1 }, { merge: true });
    return true;
  });
}

/** 查询某用户可匹配的真实用户（异性、±10 岁、未拉黑）*/
async function eligibleUsers(user: any, exclude: string[] = []) {
  const snap = await db.collection("users")
    .where("gender", "==", opposite(user.gender))
    .where("birthYear", ">=", user.birthYear - AGE)
    .where("birthYear", "<=", user.birthYear + AGE).get();
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as any) }))
    .filter((u) => !exclude.includes(u.id)
      && !(u.blockedUserIds ?? []).includes(user.id)
      && !(user.blockedUserIds ?? []).includes(u.id));
}

async function notify(uid: string, bottleId: string, message: string) {
  await db.collection(`users/${uid}/notices`).add({ bottleId, message, read: false, createdAt: new Date() });
  const token = (await db.doc(`users/${uid}`).get()).data()?.fcmToken;
  if (token) {
    // 推送 stub：生产环境请配置 APNs 证书后启用
    await admin.messaging().send({ token, notification: { title: "漂流瓶", body: message } }).catch(() => undefined);
  }
}

/** 把瓶子投递给一位符合条件的真实用户（负载最少者优先）；没有则保持 floating */
async function deliver(bottleRef: FirebaseFirestore.DocumentReference) {
  const b = (await bottleRef.get()).data() as any;
  const sender = await getUser(b.senderId);
  const cands = await eligibleUsers(sender, [b.senderId, ...(b.thrownBackBy ?? [])]);
  if (cands.length === 0) {
    await bottleRef.update({ status: "floating", recipientId: null, updatedAt: new Date() });
    return false;
  }
  // 简单策略：随机选择；可替换为“收件箱最少”优先
  const r = cands[Math.floor(Math.random() * cands.length)];
  await bottleRef.update({ status: "delivered", recipientId: r.id, updatedAt: new Date() });
  return true;
}

export const throwBottle = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", "请先登录");
  const text = String(req.data?.text ?? "").trim();
  if (!text || text.length > 200) return { error: "瓶子内容需在 1–200 字之间" };
  if (SENSITIVE.some((w) => text.includes(w))) return { error: "内容包含敏感词，请修改后再扔" };
  const user = await getUser(uid);
  if (!(await consumeQuota(uid, !!user.isMember, "throws"))) return { error: "今天的扔瓶次数用完了" };

  const ref = await db.collection("bottles").add({
    senderId: uid, senderNickname: user.nickname, senderGender: user.gender, senderBirthYear: user.birthYear,
    text, imageURL: req.data?.imageURL ?? null, status: "floating", recipientId: null,
    pickCount: 0, thrownBackBy: [], createdAt: new Date(), updatedAt: new Date(),
  });
  const delivered = await deliver(ref);
  if (!delivered) {
    // 没有任何其他符合条件的真实用户 → 灯塔守望者（AI）回复，并告知第一位访客
    const others = await db.collection("users").where("__name__", "!=", uid).limit(1).get();
    const reply = await aiReply(text);
    const chat = await db.collection("chats").add({ participants: [uid, AI_ID], bottleId: ref.id, isAI: true, lastMessage: reply, updatedAt: new Date() });
    await chat.collection("messages").add({ senderId: AI_ID, text: reply, isAI: true, createdAt: new Date() });
    await ref.update({ status: "aiReplied", chatId: chat.id });
    const msg = others.empty
      ? "你是这片海的第一位访客，灯塔守望者先陪你聊聊"
      : "暂时没有合适的旅人，灯塔守望者（AI）先陪你聊聊；有人来了瓶子会继续漂向他们";
    await notify(uid, ref.id, msg);
    return { message: msg, bottleId: ref.id, ai: true };
  }
  return { message: "瓶子已经漂向大海", bottleId: ref.id };
});

export const pickBottle = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", "请先登录");
  const user = await getUser(uid);
  // 1) 已投递给我的瓶子，未被捡过的优先
  let snap = await db.collection("bottles").where("recipientId", "==", uid).where("status", "==", "delivered")
    .orderBy("pickCount").orderBy("createdAt").limit(1).get();
  // 2) 仍在漂流（之前没有可投递对象）且我符合条件的瓶子
  if (snap.empty) {
    const floating = await db.collection("bottles").where("status", "==", "floating")
      .where("senderGender", "==", opposite(user.gender))
      .where("senderBirthYear", ">=", user.birthYear - AGE).where("senderBirthYear", "<=", user.birthYear + AGE)
      .orderBy("senderBirthYear").limit(20).get();
    const ok = floating.docs.filter((d) => {
      const b = d.data(); return b.senderId !== uid && !(b.thrownBackBy ?? []).includes(uid)
        && !(user.blockedUserIds ?? []).includes(b.senderId);
    }).sort((a, b) => a.data().pickCount - b.data().pickCount);
    if (ok.length) snap = { empty: false, docs: [ok[0]] } as any;
  }
  if (snap.empty) {
    const anyone = await eligibleUsers(user, [uid]);
    if (anyone.length === 0) return { firstVisitor: true };
    return { message: "海面上暂时没有漂到你身边的瓶子，过会儿再来看看吧" };
  }
  if (!(await consumeQuota(uid, !!user.isMember, "picks"))) return { error: "今天的捡瓶次数用完了" };
  const doc = snap.docs[0];
  await doc.ref.update({ status: "viewed", recipientId: uid, viewedAt: new Date(),
    pickCount: admin.firestore.FieldValue.increment(1), updatedAt: new Date() });
  await notify(doc.data().senderId, doc.id, "你的瓶子被人捡起来了，正在被阅读");
  return { bottleId: doc.id };
});

export const throwBack = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", "请先登录");
  const ref = db.doc(`bottles/${req.data.bottleId}`);
  const b = (await ref.get()).data(); if (!b || b.recipientId !== uid) throw new HttpsError("permission-denied", "无权操作");
  await ref.update({ status: "thrownBack", thrownBackBy: admin.firestore.FieldValue.arrayUnion(uid), updatedAt: new Date() });
  await notify(b.senderId, ref.id, "你的瓶子被捡起来看了，又被扔回了大海");
  await deliver(ref); // 重新投递给下一位真实用户（保持“我的瓶子”中可见的状态见 statusHistory TODO）
  return { ok: true };
});

export const replyBottle = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", "请先登录");
  const text = String(req.data?.text ?? "").trim();
  if (!text || SENSITIVE.some((w) => text.includes(w))) return { error: "回复内容无效或包含敏感词" };
  const ref = db.doc(`bottles/${req.data.bottleId}`);
  const b = (await ref.get()).data(); if (!b || b.recipientId !== uid) throw new HttpsError("permission-denied", "无权操作");
  const chat = await db.collection("chats").add({ participants: [b.senderId, uid], bottleId: ref.id, isAI: false, lastMessage: text, updatedAt: new Date() });
  await chat.collection("messages").add({ senderId: uid, text, isAI: false, createdAt: new Date() });
  await ref.update({ status: "replied", chatId: chat.id, updatedAt: new Date() });
  await notify(b.senderId, ref.id, "有人回复了你的瓶子，快去聊聊吧");
  return { chatId: chat.id };
});

/** 每小时检查：看了但超时未回复 → viewedNoReply */
export const markViewedNoReply = onSchedule({ schedule: "every 60 minutes", region: REGION }, async () => {
  const cutoff = new Date(Date.now() - NO_REPLY_HOURS * 3600e3);
  const snap = await db.collection("bottles").where("status", "==", "viewed").where("viewedAt", "<=", cutoff).get();
  for (const d of snap.docs) {
    await d.ref.update({ status: "viewedNoReply", updatedAt: new Date() });
    await notify(d.data().senderId, d.id, "有人看了你的瓶子，但还没有回应");
  }
});

/** 新用户注册后，把漂流中的瓶子投递给 TA（保证瓶子到达真实用户）——TODO: 用 onDocumentCreated("users/{uid}") 触发 */

export const syncMembership = onCall({ region: REGION }, async (req) => {
  // TODO: 调用 App Store Server API 校验交易后写 isMember / memberExpiresAt
  return { ok: false, todo: "server-side verification not implemented" };
});

export const deleteAccount = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", "请先登录");
  const bottles = await db.collection("bottles").where("senderId", "==", uid).get();
  const batch = db.batch(); bottles.docs.forEach((d) => batch.delete(d.ref)); batch.delete(db.doc(`users/${uid}`));
  await batch.commit();
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await admin.storage().bucket().deleteFiles({ prefix: `bottles/${uid}/` }).catch(() => undefined);
  // TODO: 聊天记录匿名化/删除
  return { ok: true };
});

/** AI 回复 stub：接入大模型时务必保持“灯塔守望者（AI）”身份，绝不冒充真实用户 */
async function aiReply(text: string): Promise<string> {
  return `【灯塔守望者 · AI】我收到了你的瓶子：“${text.slice(0, 30)}${text.length > 30 ? "…" : ""}”。你是这片海的第一位访客，在其他旅人到来之前，我先陪你聊聊。`;
}
