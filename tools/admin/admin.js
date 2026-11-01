#!/usr/bin/env node
/**
 * 漂流瓶 · 举报审核命令行（无网页后台）
 * 认证：gcloud auth application-default login（或 GOOGLE_APPLICATION_CREDENTIALS 指向服务账号 JSON，切勿提交）
 * 用法：
 *   node admin.js list                 列出待处理举报
 *   node admin.js ban <reportId>       确认举报 → 封禁被举报账号与设备
 *   node admin.js dismiss <reportId>   驳回举报
 *   node admin.js grant-admin <uid>    给某个账号加 admin 声明（可在 App 内调用 reviewReport）
 * 项目：环境变量 FIREBASE_PROJECT 或 .firebaserc 的 default
 */
const admin = require("firebase-admin");
const fs = require("fs"), path = require("path");

function projectId() {
  if (process.env.FIREBASE_PROJECT) return process.env.FIREBASE_PROJECT;
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, "../../.firebaserc"), "utf8")).projects.default; } catch { return undefined; }
}
admin.initializeApp({ projectId: projectId() });
const db = admin.firestore();
const fmt = (v) => (v && v.toDate ? v.toDate().toLocaleString("zh-CN", { timeZone: "Asia/Shanghai" }) : "-");

async function list() {
  const snap = await db.collection("reports").where("status", "==", "pending").orderBy("createdAt").limit(100).get();
  if (snap.empty) return console.log("没有待处理的举报 ✓");
  for (const d of snap.docs) {
    const r = d.data();
    const target = (await db.doc(`users/${r.targetUserId}`).get()).data() || {};
    let excerpt = "";
    if (r.bottleId) { const b = (await db.doc(`bottles/${r.bottleId}`).get()).data(); if (b) excerpt = b.text.slice(0, 60); }
    console.log(`\n[${d.id}] ${fmt(r.createdAt)}\n  被举报：${target.nickname || "?"} (${r.targetUserId})${target.banned ? " [已封禁]" : ""}\n  原因：${r.reason || "-"}${excerpt ? `\n  瓶子：${excerpt}` : ""}`);
  }
  console.log(`\n共 ${snap.size} 条。处理：node admin.js ban <id> | dismiss <id>`);
}

async function review(id, status) {
  const ref = db.doc(`reports/${id}`);
  const r = await ref.get(); if (!r.exists) throw new Error("举报不存在：" + id);
  await ref.update({ status, reviewedBy: "cli", reviewedAt: new Date() });
  console.log(status === "confirmed" ? "已确认，封禁将由云函数 onReportConfirmed 执行" : "已驳回");
}

(async () => {
  const [cmd, arg] = process.argv.slice(2);
  if (cmd === "list") await list();
  else if (cmd === "ban" && arg) await review(arg, "confirmed");
  else if (cmd === "dismiss" && arg) await review(arg, "dismissed");
  else if (cmd === "grant-admin" && arg) { await admin.auth().setCustomUserClaims(arg, { admin: true }); console.log("已授予 admin：" + arg + "（该账号需重新登录生效）"); }
  else console.log("用法：node admin.js list | ban <reportId> | dismiss <reportId> | grant-admin <uid>");
  process.exit(0);
})().catch((e) => { console.error(e.message || e); process.exit(1); });
