/**
 * App Store Server Notifications V2（HTTPS 端点）
 * App Store Connect → App 信息 → App Store 服务器通知 → 填入本函数 URL（生产/沙盒各一条，版本选 V2）。
 * 签名校验：SignedDataVerifier（Apple 根证书在 functions/certs/*.cer）。
 * CONSUMPTION_REQUEST：仅在用户于 App 内同意（users.consumptionConsent == true）时，
 *   通过 App Store Server API sendConsumptionData 回传使用情况。退款最终由 Apple 决定。
 * 配置（Secret Manager，勿提交）：APPLE_IAP_KEY（.p8 内容）、APPLE_IAP_KEY_ID、APPLE_IAP_ISSUER_ID；
 * 环境变量（functions/.env）：APPLE_BUNDLE_ID、APPLE_APP_ID、APPLE_ENV。
 */
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  AppStoreServerAPIClient, Environment, NotificationTypeV2, ConsumptionRequest, ConsumptionStatus, DeliveryStatus,
  Platform, AccountTenure, PlayTime, UserStatus, LifetimeDollarsPurchased, LifetimeDollarsRefunded,
  JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import { RefundPreference } from "@apple/app-store-server-library/dist/models/RefundPreference";
import { getVerifier, PRODUCTS } from "./appstore";

const APPLE_IAP_KEY = defineSecret("APPLE_IAP_KEY");
const APPLE_IAP_KEY_ID = defineSecret("APPLE_IAP_KEY_ID");
const APPLE_IAP_ISSUER_ID = defineSecret("APPLE_IAP_ISSUER_ID");
const REGION = "asia-east2";
const toDate = (v: any): Date | null => (v?.toDate ? v.toDate() : v instanceof Date ? v : null);

function apiClient(): AppStoreServerAPIClient {
  const env = process.env.APPLE_ENV === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  return new AppStoreServerAPIClient(APPLE_IAP_KEY.value(), APPLE_IAP_KEY_ID.value(), APPLE_IAP_ISSUER_ID.value(),
    process.env.APPLE_BUNDLE_ID ?? "com.limuye.driftbottle", env);
}

/** 由 syncMembership 写入的 subscriptions/{originalTransactionId} 找到用户 */
async function uidFor(originalTransactionId?: string): Promise<string | null> {
  if (!originalTransactionId) return null;
  const d = await admin.firestore().doc(`subscriptions/${originalTransactionId}`).get();
  return (d.data()?.uid as string) ?? null;
}

function tenure(created: Date | null): AccountTenure {
  if (!created) return AccountTenure.UNDECLARED;
  const days = (Date.now() - created.getTime()) / 86400e3;
  if (days < 3) return AccountTenure.ZERO_TO_THREE_DAYS;
  if (days < 10) return AccountTenure.THREE_DAYS_TO_TEN_DAYS;
  if (days < 30) return AccountTenure.TEN_DAYS_TO_THIRTY_DAYS;
  if (days < 90) return AccountTenure.THIRTY_DAYS_TO_NINETY_DAYS;
  if (days < 180) return AccountTenure.NINETY_DAYS_TO_ONE_HUNDRED_EIGHTY_DAYS;
  if (days < 365) return AccountTenure.ONE_HUNDRED_EIGHTY_DAYS_TO_THREE_HUNDRED_SIXTY_FIVE_DAYS;
  return AccountTenure.GREATER_THAN_THREE_HUNDRED_SIXTY_FIVE_DAYS;
}

async function sendConsumption(uid: string, tx: JWSTransactionDecodedPayload) {
  const u = (await admin.firestore().doc(`users/${uid}`).get()).data();
  if (!u?.consumptionConsent) { logger.info("CONSUMPTION_REQUEST: 用户未同意共享使用数据，不回传", { uid }); return; }
  if (!tx.transactionId) return;
  const purchased = tx.purchaseDate ?? 0;
  const lastUse = toDate(u.stats?.lastActiveAt)?.getTime() ?? 0;
  const used = (u.stats?.thrown ?? 0) + (u.stats?.picked ?? 0) > 0 && lastUse >= purchased;
  const req: ConsumptionRequest = {
    customerConsented: true,
    consumptionStatus: used ? ConsumptionStatus.PARTIALLY_CONSUMED : ConsumptionStatus.NOT_CONSUMED,
    platform: Platform.APPLE,
    sampleContentProvided: true,                      // 免费档（3/3 每天）即试用内容
    deliveryStatus: DeliveryStatus.DELIVERED_AND_WORKING_PROPERLY, // 权益开通即时生效
    appAccountToken: tx.appAccountToken ?? "",
    accountTenure: tenure(toDate(u.serverCreatedAt)),
    playTime: PlayTime.UNDECLARED,
    lifetimeDollarsPurchased: LifetimeDollarsPurchased.UNDECLARED,
    lifetimeDollarsRefunded: LifetimeDollarsRefunded.UNDECLARED,
    userStatus: u.banned ? UserStatus.SUSPENDED : UserStatus.ACTIVE,
    refundPreference: RefundPreference.PREFER_DECLINE, // 虚拟服务即时生效，倾向不退款（最终由 Apple 决定）
  };
  await apiClient().sendConsumptionData(tx.transactionId, req);
  logger.info("CONSUMPTION_REQUEST: 已回传使用数据", { uid, used, thrown: u.stats?.thrown ?? 0, picked: u.stats?.picked ?? 0 });
}

export const appStoreNotifications = onRequest(
  { region: REGION, secrets: [APPLE_IAP_KEY, APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID] },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("POST only"); return; }
    const signedPayload = req.body?.signedPayload;
    if (typeof signedPayload !== "string") { res.status(400).send("missing signedPayload"); return; }
    const db = admin.firestore();
    try {
      const v = getVerifier();
      const n = await v.verifyAndDecodeNotification(signedPayload);
      const type = n.notificationType, sub = n.subtype;
      if (type === NotificationTypeV2.TEST) { logger.info("App Store 测试通知 OK"); res.status(200).send("ok"); return; }
      const signedTx = n.data?.signedTransactionInfo;
      const tx = signedTx ? await v.verifyAndDecodeTransaction(signedTx) : null;
      const renewal = n.data?.signedRenewalInfo ? await v.verifyAndDecodeRenewalInfo(n.data.signedRenewalInfo) : null;
      const otid = tx?.originalTransactionId ?? renewal?.originalTransactionId;
      // 幂等：同一 notificationUUID 只处理一次
      if (n.notificationUUID) {
        const seen = db.doc(`storeNotifications/${n.notificationUUID}`);
        if ((await seen.get()).exists) { res.status(200).send("dup"); return; }
        await seen.set({ type, subtype: sub ?? null, originalTransactionId: otid ?? null, receivedAt: new Date() });
      }
      const uid = await uidFor(otid);
      if (!uid) { logger.warn("找不到订阅对应的用户（客户端尚未 syncMembership）", { type, otid }); res.status(200).send("no user"); return; }
      const userRef = db.doc(`users/${uid}`);
      const expires = tx?.expiresDate ? new Date(tx.expiresDate) : null;
      const product = PRODUCTS[tx?.productId ?? ""];

      switch (type) {
        case NotificationTypeV2.SUBSCRIBED:
        case NotificationTypeV2.DID_RENEW:
        case NotificationTypeV2.OFFER_REDEEMED:
        case NotificationTypeV2.REFUND_REVERSED: {
          const active = !!product && !!expires && expires.getTime() > Date.now() && !tx?.revocationDate;
          await userRef.update({ isMember: active, memberTier: active ? product.tier : "free", memberExpiresAt: expires });
          break;
        }
        case NotificationTypeV2.EXPIRED:
        case NotificationTypeV2.GRACE_PERIOD_EXPIRED:
        case NotificationTypeV2.REFUND:
        case NotificationTypeV2.REVOKE:
          await userRef.update({ isMember: false, memberTier: "free", memberExpiresAt: expires ?? new Date(),
            ...(type === NotificationTypeV2.REFUND ? { refundedAt: new Date() } : {}) });
          break;
        case NotificationTypeV2.DID_CHANGE_RENEWAL_STATUS:
          // 仅记录自动续期开关；权益保留到到期日
          await userRef.update({ memberAutoRenew: renewal?.autoRenewStatus === 1 });
          break;
        case NotificationTypeV2.CONSUMPTION_REQUEST:
          if (tx) await sendConsumption(uid, tx);
          break;
        default:
          logger.info("忽略的通知类型", { type, sub });
      }
      if (otid) await db.doc(`subscriptions/${otid}`).set({ lastNotification: type, updatedAt: new Date(), expiresAt: expires }, { merge: true });
      res.status(200).send("ok");
    } catch (err: any) {
      logger.error("App Store 通知处理失败", err);
      // 校验失败返回 400；Apple 会对非 200 重试
      res.status(400).send("invalid");
    }
  });
