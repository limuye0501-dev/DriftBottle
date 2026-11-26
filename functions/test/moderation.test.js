const assert = require("assert");
const { moderateTextLocal } = require("../lib/moderation");
const { SEED_DATA } = require("../lib/seeds.data");

function walk(value, out) {
  if (typeof value === "string") out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => walk(v, out));
  else if (value && typeof value === "object") Object.values(value).forEach((v) => walk(v, out));
}

const block = [
  "fuck this", "this is porn", "nigger", "kill yourself", "child porn",
  "约炮吗", "操你妈", "씨발놈", "fuck@mail.com", "hello@example.com",
  "https://spam.example.com/x", "salope", "ficken", "блядь", "kontol",
  "siktir", "địt", "شرموطة", "ควย", "섹스해", "nazi", "te voy a matar",
];
for (const s of block) assert.strictEqual(moderateTextLocal(s).ok, false, "should block: " + s);

const allow = [
  "class photo", "cocktail hour", "Essex sunset", "peacock", "Scunthorpe",
  "操场跑步", "陌生的海边", "보지 않다", "therapist", "grape", "I love this sunset",
  "Dear stranger, the sea is quiet tonight",
];
for (const s of allow) assert.strictEqual(moderateTextLocal(s).ok, true, "should allow: " + s);

const seeds = [];
walk(SEED_DATA, seeds);
const hit = seeds.filter((s) => !moderateTextLocal(s).ok);
assert.deepStrictEqual(hit, [], "keeper letters must stay readable");
console.log("moderation ok", seeds.length, "seed strings");
