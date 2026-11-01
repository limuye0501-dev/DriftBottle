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

export const ANNUAL_PRODUCT_ID = "com.example.driftbottle.annual"; // 占位，¥98/年

let verifier: SignedDataVerifier | null = null;
function getVerifier(): SignedDataVerifier {
  if (verifier) return verifier;
  const dir = path.join(__dirname, "..", "certs");
  const roots = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".cer")).map((f) => fs.readFileSync(path.join(dir, f))) : [];
  if (roots.length === 0) throw new Error("缺少 Apple 根证书（functions/certs/*.cer）");
  const env = process.env.APPLE_ENV === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appId = process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined;
  verifier = new SignedDataVerifier(roots, true, env, process.env.APPLE_BUNDLE_ID ?? "com.example.driftbottle", appId);
  return verifier;
}

export interface MembershipInfo { isMember: boolean; expiresAt: Date | null; originalTransactionId?: string; appAccountToken?: string }

export async function verifyTransaction(signedTransaction: string): Promise<MembershipInfo> {
  const tx: JWSTransactionDecodedPayload = await getVerifier().verifyAndDecodeTransaction(signedTransaction);
  const expires = tx.expiresDate ? new Date(tx.expiresDate) : null;
  const active = tx.productId === ANNUAL_PRODUCT_ID && !tx.revocationDate && !!expires && expires.getTime() > Date.now();
  return { isMember: active, expiresAt: expires, originalTransactionId: tx.originalTransactionId, appAccountToken: tx.appAccountToken };
}
// TODO: App Store Server Notifications V2 端点（续订/退款/过期实时更新），用 verifier.verifyAndDecodeNotification
