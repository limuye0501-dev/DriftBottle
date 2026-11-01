/**
 * 推送（FCM → APNs）。克制原则：
 *  - 每位用户每小时最多 8 条；同一会话的聊天推送至少间隔 2 分钟（期间的新消息不再单独推送，打开 App 即可看到）
 *  - 北京时间 23:00–08:00 静默送达（无声音，仅出现在通知中心）
 *  - 无效 token 自动清除
 */
import * as admin from "firebase-admin";

const HOURLY_CAP = 8, CHAT_GAP_MS = 2 * 60e3;
const db = () => admin.firestore();

function quietHour(): boolean {
  const h = new Date(Date.now() + 8 * 3600e3).getUTCHours();
  return h >= 23 || h < 8;
}

/** 返回 true 表示允许发送（并记账） */
async function allow(uid: string, key: string, gapMs: number): Promise<boolean> {
  const ref = db().doc(`pushThrottle/${uid}`);
  return db().runTransaction(async (t) => {
    const d = (await t.get(ref)).data() ?? {};
    const now = Date.now(), hour = Math.floor(now / 3600e3);
    const count = d.hour === hour ? (d.count ?? 0) : 0;
    const last = d.last?.[key] ?? 0;
    if (count >= HOURLY_CAP || now - last < gapMs) return false;
    t.set(ref, { hour, count: count + 1, last: { ...(d.last ?? {}), [key]: now } }, { merge: true });
    return true;
  });
}

export async function sendPush(uid: string, opts: { title: string; body: string; key: string; gapMs?: number; data?: Record<string, string> }) {
  const userRef = db().doc(`users/${uid}`);
  const u = (await userRef.get()).data();
  const token = u?.fcmToken as string | undefined;
  if (!token || u?.banned) return;
  if (!(await allow(uid, opts.key, opts.gapMs ?? 0))) return;
  const quiet = quietHour();
  try {
    await admin.messaging().send({
      token,
      notification: { title: opts.title, body: opts.body },
      data: opts.data ?? {},
      apns: { payload: { aps: { ...(quiet ? {} : { sound: "default" }), "thread-id": opts.key, "interruption-level": quiet ? "passive" : "active" } } },
    });
  } catch (err: any) {
    const code = err?.errorInfo?.code ?? err?.code;
    if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
      await userRef.update({ fcmToken: admin.firestore.FieldValue.delete() }).catch(() => undefined);
    }
  }
}

export const CHAT_GAP = CHAT_GAP_MS;
