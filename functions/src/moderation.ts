/**
 * 服务端内容预审：关键词 + 正则 + 可插拔的审核 API（如阿里云内容安全、腾讯云天御、OpenAI moderation 等）
 * 投递前调用；命中则拒绝扔出。
 */
/** reason 为本地化 key（mod.*），或外部审核 API 返回的原文 */
export interface ModerationResult { ok: boolean; reason?: string }

const PORN = ["色情", "裸聊", "约炮", "一夜情", "援交", "包养", "黄片", "成人视频", "看片"];
const ILLEGAL = ["赌博", "博彩", "代孕", "毒品", "冰毒", "枪支", "刷单", "贷款", "加微信转账"];

/** 引流/联系方式外泄：只在“联系方式关键词 + 类账号字符串”同时出现时拦截，单纯提到“微信”不拦 */
const CONTACT_KW = "(?:微信|威信|薇信|徽信|v信|vx|wx|weixin|wechat|加v|\\+v|qq|扣扣|企鹅|球球|抖音号?|小红书号?|手机号?|电话|加我|联系我|私聊我|扫码|二维码" +
  // 海外常见站外联系方式（仍需与“像账号的字符串”同时出现才拦截）
  "|telegram|телеграм|tg|whatsapp|whats ?app|ватсап|واتساب|wa|line(?: ?id)?|ライン|kakao(?:talk)?|카톡|카카오톡|zalo|instagram|insta|ig|ins|snapchat|snap|viber|вайбер|skype|discord|facebook|fb|messenger|tiktok|signal|wechat id|vk|вк" +
  "|add me|dm me|contact me|agrégame|agregame|me adiciona|ekle beni|hubungi|liên hệ|kết bạn|追加して|연락)";
const HANDLE = "(?:(?=[a-z0-9_-]*\\d)[a-z][a-z0-9_-]{5,19}|\\d{5,})"; // 字母开头 6–20 位且含数字（像账号而非普通单词），或 5 位以上数字
const DIVERSION: { re: RegExp; reason: string }[] = [
  { re: new RegExp(`${CONTACT_KW}[\\s:：号是为=\\-~]{0,4}${HANDLE}`, "i"), reason: "mod.contact" },
  { re: new RegExp(`${HANDLE}[\\s,，]{0,2}(?:是我的?)?${CONTACT_KW}`, "i"), reason: "mod.contact" },
  { re: /(?<!\d)\d{7,}(?!\d)/, reason: "mod.phone" }, // 7 位以上数字（规整后可识别变形）
  { re: /(https?:\/\/|www\.|t\.me\/|[a-z0-9-]+\.(com|cn|net|top|xyz|io|me|vn|ru|jp|kr|br|tr|id)\b)/i, reason: "mod.link" },
];

/** 把常见变形（全角、零宽、空格、中文数字）规整后再匹配 */
export function normalize(s: string): string {
  const cn: Record<string, string> = { 零: "0", 〇: "0", 一: "1", 壹: "1", 二: "2", 贰: "2", 三: "3", 叁: "3", 四: "4", 肆: "4", 五: "5", 伍: "5", 六: "6", 陆: "6", 七: "7", 柒: "7", 八: "8", 捌: "8", 九: "9", 玖: "9" };
  return s
    .replace(/[\uFF01-\uFF5E]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0))
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/[零〇一壹二贰三叁四肆五伍六陆七柒八捌九玖]/g, (c) => cn[c])
    .replace(/(\d)[\s.\-_·•]+(?=\d)/g, "$1")
    .toLowerCase();
}

export function moderateTextLocal(raw: string): ModerationResult {
  const s = normalize(raw);
  if (PORN.some((w) => s.includes(w))) return { ok: false, reason: "mod.porn" };
  if (ILLEGAL.some((w) => s.includes(w))) return { ok: false, reason: "mod.illegal" };
  for (const d of DIVERSION) if (d.re.test(s)) return { ok: false, reason: d.reason };
  return { ok: true };
}

/** 外部审核 API 钩子：配置 MODERATION_API_URL / MODERATION_API_KEY 后启用（通过 Secret Manager，切勿提交到仓库） */
async function moderateRemote(text: string, imageURL?: string | null): Promise<ModerationResult> {
  const url = process.env.MODERATION_API_URL, key = process.env.MODERATION_API_KEY;
  if (!url || !key) return { ok: true };
  try {
    const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
      body: JSON.stringify({ text, imageURL }) });
    const j: any = await r.json();
    // 约定返回 { flagged: boolean, reason?: string }，按实际服务商适配
    return j.flagged ? { ok: false, reason: j.reason ?? "mod.generic" } : { ok: true };
  } catch {
    return { ok: true }; // 远程失败时降级为仅本地规则（可改为 fail-closed）
  }
}

/** 图片：二维码/色情识别需外部服务（本地无法可靠识别），统一走 moderateRemote */
export async function moderate(text: string, imageURL?: string | null): Promise<ModerationResult> {
  const local = moderateTextLocal(text);
  if (!local.ok) return local;
  return moderateRemote(text, imageURL);
}
