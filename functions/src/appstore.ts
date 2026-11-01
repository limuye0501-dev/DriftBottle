/**
 * App Store Server API：校验 StoreKit 2 交易 JWS（x5c 证书链 → Apple Root CA G3）
 * 配置（占位，均通过环境变量/Secret Manager，勿提交到仓库）：
 *  APPLE_BUNDLE_ID   例如 com.example.driftbottle
 *  APPLE_APP_ID      App Store 数字 App ID（生产环境必填）
 *  APPLE_ENV         Sandbox | Production
 *  Apple 根证书：下载 AppleRootCA-G3.cer 放到 functions/certs/（公开证书，可提交）
 */
import { SignedDataVerifier, Environment, JWSTransactionDecodedPayload } from "@apple/app-store-server-library";
import * as fs from "fs";
import * as path from "path";

/** 订阅组「漂流瓶会员」内的两个自动续期商品（占位 ID）。不提供免费试用。 */
export type Tier = "free" | "monthly" | "annual";
export const PRODUCTS: Record<string, { tier: Tier; rank: number }> = {
  "com.example.driftbottle.monthly": { tier: "monthly", rank: 1 }, // 月卡 ¥8/月
  "com.example.driftbottle.annual": { tier: "annual", rank: 2 },   // 年卡 ¥88/年
};
/** 每日扔/捡次数（服务端为准）。年卡对用户展示「不限次数」，服务端保留隐藏的防刷上限 200 次/天 */
export const ANNUAL_ABUSE_CAP = 200;
export const TIER_QUOTA: Record<Tier, number> = { free: 5, monthly: 20, annual: ANNUAL_ABUSE_CAP };
export const isUnlimited = (t: Tier) => t === "annual";
/** 年卡专属瓶子样式 */
export const EXCLUSIVE_STYLES = ["moonlight", "amber", "sakura"];

let verifier: SignedDataVerifier | null = null;
export function getVerifier(): SignedDataVerifier {
  if (verifier) return verifier;
  const dir = path.join(__dirname, "..", "certs");
  const roots = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".cer")).map((f) => fs.readFileSync(path.join(dir, f))) : [];
  if (roots.length === 0) throw new Error("缺少 Apple 根证书（functions/certs/*.cer）");
  const env = process.env.APPLE_ENV === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appId = process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined;
  verifier = new SignedDataVerifier(roots, true, env, process.env.APPLE_BUNDLE_ID ?? "com.example.driftbottle", appId);
  return verifier;
}

export interface MembershipInfo { isMember: boolean; tier: Tier; expiresAt: Date | null; originalTransactionId?: string; appAccountToken?: string }

export async function verifyTransaction(signedTransaction: string): Promise<MembershipInfo> {
  const tx: JWSTransactionDecodedPayload = await getVerifier().verifyAndDecodeTransaction(signedTransaction);
  const expires = tx.expiresDate ? new Date(tx.expiresDate) : null;
  const p = PRODUCTS[tx.productId ?? ""];
  const active = !!p && !tx.revocationDate && !!expires && expires.getTime() > Date.now();
  return { isMember: active, tier: active ? p.tier : "free", expiresAt: expires, originalTransactionId: tx.originalTransactionId, appAccountToken: tx.appAccountToken };
}
// App Store Server Notifications V2 端点见 storeNotifications.ts
