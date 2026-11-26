/**
 * 官方漂流信与灯塔守夜人。真人瓶子优先；海里没有别人的瓶子时，仍发一封可阅读的信。
 * en / zh-Hans / ja / ko / es 各有一池；其余界面语言回退英文。
 * 与 DriftBottle/Resources/Seeds.json 同源（tools/seeds/build_library.py）。
 */
import { SEED_DATA } from "./seeds.data";

export const KEEPER_ID = "lighthouse-keeper";
export const KEEPER_AGE = SEED_DATA.keeperAge;
export const KEEPER_GENDER = SEED_DATA.keeperGender;
export const STYLES = ["classic", "moonlight", "amber", "sakura"] as const;

const LOCALES = ["en", "zh-Hans", "ja", "ko", "es"] as const;
export type SeedLocale = (typeof LOCALES)[number];

export function seedLocale(raw?: string): SeedLocale {
  const s = (raw ?? "en").replace(/_/g, "-");
  if ((LOCALES as readonly string[]).includes(s)) return s as SeedLocale;
  const lower = s.toLowerCase();
  if (lower === "zh" || lower.startsWith("zh-hans") || lower.startsWith("zh-cn")) return "zh-Hans";
  return "en";
}

export function keeperName(loc?: string): string {
  return SEED_DATA.keeperName[seedLocale(loc)];
}

/** 没捡过的下一封；池子用尽后从头再来（reset=true 时调用方清空已读列表）。 */
export function nextSeed(loc: string | undefined, picked: string[]): { id: string; text: string; reset: boolean } {
  const lang = seedLocale(loc);
  const pool = SEED_DATA.bottles[lang];
  const seen = new Set(picked);
  for (let i = 0; i < pool.length; i++) {
    const id = `${lang}:${i}`;
    if (!seen.has(id)) return { id, text: pool[i], reset: false };
  }
  return { id: `${lang}:0`, text: pool[0], reset: true };
}

export function keeperReply(loc: string | undefined, salt: number): string {
  const list = SEED_DATA.replies[seedLocale(loc)];
  return list[Math.abs(salt | 0) % list.length];
}

export function welcomeCopy(loc?: string): { bottle: string; chat: string; name: string } {
  const lang = seedLocale(loc);
  return { bottle: SEED_DATA.welcomeBottle[lang], chat: SEED_DATA.welcomeChat[lang], name: SEED_DATA.keeperName[lang] };
}

export function isKeeperBottle(b: { seed?: boolean; welcome?: boolean; senderId?: string } | null | undefined): boolean {
  return !!b && (b.seed === true || b.welcome === true || b.senderId === KEEPER_ID);
}
