/** 服务端本地化：推送、通知、错误提示按用户 locale 输出；未知语言回退 en。数据由 tools/i18n/build.py 生成。 */
import { STRINGS, LANGS } from "./i18n.data";

export function resolveLocale(raw?: unknown): string {
  if (typeof raw !== "string" || !raw) return "en";
  const s = raw.replace(/_/g, "-");
  if ((LANGS as readonly string[]).includes(s)) return s;
  const lower = s.toLowerCase();
  if (lower.startsWith("zh")) return /hant|tw|hk|mo/.test(lower) ? "zh-Hant" : "zh-Hans";
  if (lower.startsWith("pt")) return "pt-BR";
  const base = lower.split("-")[0];
  return (LANGS as readonly string[]).find((l) => l.toLowerCase() === base) ?? "en";
}

/** 支持 %@ / %ld / %1$@ / %2$ld */
export function t(locale: string | undefined, key: string, ...args: (string | number)[]): string {
  const loc = resolveLocale(locale);
  const fmt = STRINGS[loc]?.[key] ?? STRINGS.en[key];
  if (fmt === undefined) return key;
  let i = 0;
  return fmt.replace(/%(?:(\d+)\$)?(@|ld|d)/g, (_m, pos) => String(args[pos ? Number(pos) - 1 : i++] ?? ""));
}

/** 审核原因：若是 key（如 "mod.contact"）则翻译，否则（外部 API 原文）原样返回 */
export const reason = (locale: string | undefined, r?: string) =>
  r && /^(mod|img)\.[a-z]+$/.test(r) ? t(locale, r) : (r ?? t(locale, "mod.generic"));
