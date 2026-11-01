/**
 * 图片审核：Google Cloud Vision SafeSearch（需在 GCP 启用 Cloud Vision API）。
 * 宽松策略：仅拦截 adult / violence 为 LIKELY 或 VERY_LIKELY，以及 racy 为 VERY_LIKELY。
 */
import { ImageAnnotatorClient } from "@google-cloud/vision";

let client: ImageAnnotatorClient | null = null;
const STRONG = ["LIKELY", "VERY_LIKELY"];

export interface ImageVerdict { ok: boolean; reason?: string; scores?: Record<string, string> }

export async function checkImage(gcsUri: string): Promise<ImageVerdict> {
  client ??= new ImageAnnotatorClient();
  const [res] = await client.safeSearchDetection(gcsUri);
  const s = res.safeSearchAnnotation;
  if (!s) return { ok: true };
  const scores = { adult: String(s.adult), violence: String(s.violence), racy: String(s.racy) };
  if (STRONG.includes(scores.adult)) return { ok: false, reason: "图片涉及色情内容", scores };
  if (STRONG.includes(scores.violence)) return { ok: false, reason: "图片涉及暴力血腥内容", scores };
  if (scores.racy === "VERY_LIKELY") return { ok: false, reason: "图片过于暴露", scores };
  return { ok: true, scores };
}

/** Storage 路径 → Firestore 文档 ID（不能含 /） */
export const reviewId = (path: string) => path.replace(/\//g, "__");
