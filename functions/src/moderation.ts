/**
 * 服务端内容预审：关键词 + 正则 + 可插拔的审核 API（如阿里云内容安全、腾讯云天御、OpenAI moderation 等）
 * 投递前调用；命中则拒绝扔出。
 */
/** reason 为本地化 key（mod.*），或外部审核 API 返回的原文 */
export interface ModerationResult { ok: boolean; reason?: string }

/**
 * 与 DriftBottle/Services/Services.swift 的 SensitiveWordFilter 保持一致（客户端只判断命中与否）。
 * 中日韩用子串（这些词本身不会嵌进日常用词）；拉丁文用 Unicode 词边界，避免 class / grape / therapist。
 * 不拦 sex、shit、joder、puto、보지（韩语「보지 않다」=没看见）这类日常词。
 */
const PORN_SUB = [
  "色情", "裸聊", "约炮", "一夜情", "援交", "包养", "黄片", "成人视频", "看片", "强奸", "轮奸", "操你妈",
  "ポルノ", "エロ動画", "エロ画像", "援助交際", "強姦", "レイプ", "セックス", "ちんこ", "ちんぽ", "まんこ", "ファック",
  "야동", "포르노", "강간", "창녀",
];
const ABUSE_SUB = ["傻逼", "去死", "支那", "黑鬼", "殺すぞ", "氏ね", "병신"];
const ILLEGAL = ["赌博", "博彩", "代孕", "毒品", "冰毒", "枪支", "刷单", "贷款", "加微信转账"];
const SEXUAL_TERMS = [
  "porn", "pornography", "porno", "hentai", "nude", "nudes", "nudity",
  "blowjob", "handjob", "dickpic", "nsfw", "onlyfans", "dildo", "orgasm",
  "cumshot", "creampie", "deepthroat", "gangbang", "threesome", "milf", "incest",
  "fuck", "fucking", "fucked", "fucker", "whore", "slut", "cunt",
  "rape", "rapist", "raping", "pedophile", "pedo",
  "pornografia", "pornografía", "prostituta", "violacion", "violación",
];
const ABUSE_TERMS = [
  "bitch", "retard", "retarded", "faggot", "tranny",
  "nigger", "nigga", "chink", "kike", "spic", "wetback", "kys", "maricon", "maricón",
];
const SEXUAL_PHRASES = ["child porn"];
const ABUSE_PHRASES = ["kill yourself", "kill urself", "hijo de puta", "hija de puta"];
const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
function boundaryRe(terms: string[], phrases: string[]): RegExp {
  const alt = [...terms.map(esc), ...phrases.map((p) => p.split(/\s+/).map(esc).join("\\s+"))].join("|");
  return new RegExp(`(?<![\\p{L}\\p{N}])(?:${alt})(?![\\p{L}\\p{N}])`, "u");
}
const SEXUAL_RE = boundaryRe(SEXUAL_TERMS, SEXUAL_PHRASES);
const ABUSE_RE = boundaryRe(ABUSE_TERMS, ABUSE_PHRASES);

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
  if (PORN_SUB.some((w) => s.includes(w)) || SEXUAL_RE.test(s)) return { ok: false, reason: "mod.porn" };
  if (ABUSE_SUB.some((w) => s.includes(w)) || ABUSE_RE.test(s)) return { ok: false, reason: "mod.illegal" };
  if (ILLEGAL.some((w) => s.includes(w))) return { ok: false, reason: "mod.illegal" };
  for (const d of DIVERSION) if (d.re.test(s)) return { ok: false, reason: d.reason };
  return { ok: true };
}

/**
 * 外部审核 API：仅当 MODERATION_API_URL 与 MODERATION_API_KEY 都配置时才调用。
 * 未配置不是“全部放行”——本地词表已经给出结论，这里只是不再追加一次远程判断。
 * 远程失败同样退回本地结论，而不是另记一次通过。
 */
async function moderateRemote(text: string, imageURL?: string | null): Promise<ModerationResult | null> {
  const url = process.env.MODERATION_API_URL, key = process.env.MODERATION_API_KEY;
  if (!url || !key) return null;
  const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
    body: JSON.stringify({ text, imageURL }) });
  const j: any = await r.json();
  // 约定返回 { flagged: boolean, reason?: string }，按实际服务商适配
  return j.flagged ? { ok: false, reason: j.reason ?? "mod.generic" } : { ok: true };
}

/** 图片：二维码/色情识别需外部服务（本地无法可靠识别）。文本始终先过本地词表。 */
export async function moderate(text: string, imageURL?: string | null): Promise<ModerationResult> {
  const local = moderateTextLocal(text);
  if (!local.ok) return local;
  try {
    const remote = await moderateRemote(text, imageURL);
    if (remote && !remote.ok) return remote;
  } catch {
    // 远程不可用：保留本地结论（此时 local.ok 为 true）
  }
  return local;
}
