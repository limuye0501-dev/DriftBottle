#!/usr/bin/env node
/**
 * Drift Bottle moderation queue.
 *
 * Lists open reports, removes the reported content, and bans the author so they
 * cannot throw or reply. Act on every open report within 24 hours.
 *
 * Auth: `gcloud auth application-default login`
 *    or GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account JSON (do not commit it).
 * Project: FIREBASE_PROJECT, or the default project in .firebaserc.
 *
 *   node scripts/moderate.js list
 *   node scripts/moderate.js remove <reportId>     delete the author's bottles and messages, ban the uid and device
 *   node scripts/moderate.js dismiss <reportId>
 *   node scripts/moderate.js grant-admin <uid>
 *
 * `ban` is an alias of `remove`.
 */
const fs = require("fs");
const path = require("path");

function loadAdmin() {
  const candidates = [
    "firebase-admin",
    path.join(__dirname, "node_modules", "firebase-admin"),
    path.join(__dirname, "../tools/admin/node_modules/firebase-admin"),
    path.join(__dirname, "../functions/node_modules/firebase-admin"),
  ];
  for (const candidate of candidates) {
    try { return require(candidate); } catch { /* try the next location */ }
  }
  throw new Error("firebase-admin is not installed. From the repo root: cd tools/admin && npm install");
}

function projectId() {
  if (process.env.FIREBASE_PROJECT) return process.env.FIREBASE_PROJECT;
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, "../.firebaserc"), "utf8")).projects.default;
  } catch {
    return undefined;
  }
}

const admin = loadAdmin();
admin.initializeApp({ projectId: projectId() });
const db = admin.firestore();

const fmt = (v) => (v && v.toDate ? v.toDate().toISOString() : "-");
const authorOf = (r) => r.authorUid || r.targetUserId || "";

function isOpen(data) {
  return !data.status || data.status === "pending";
}

async function list() {
  const snap = await db.collection("reports").orderBy("createdAt").limit(200).get();
  const open = snap.docs.filter((d) => isOpen(d.data()));
  if (!open.length) {
    console.log("No open reports.");
    return;
  }
  for (const d of open) {
    const r = d.data();
    const author = authorOf(r);
    const target = author ? (await db.doc(`users/${author}`).get()).data() || {} : {};
    let excerpt = "";
    if (r.bottleId) {
      const b = (await db.doc(`bottles/${r.bottleId}`).get()).data();
      if (b && b.text) excerpt = String(b.text).slice(0, 80);
    }
    console.log(`\n[${d.id}] ${fmt(r.createdAt)}`);
    console.log(`  author: ${target.nickname || "?"} (${author})${target.banned ? " [banned]" : ""}`);
    console.log(`  reporter: ${r.reporterId || "-"}`);
    console.log(`  reason: ${r.reason || "-"}${r.bottleId ? `\n  bottle: ${r.bottleId}` : ""}${r.messageId ? `\n  message: ${r.messageId}` : ""}`);
    if (excerpt) console.log(`  text: ${excerpt}`);
  }
  console.log(`\n${open.length} open. Next: node scripts/moderate.js remove <reportId>`);
}

async function commitDeletes(docs) {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

/** Delete the author's bottles and messages, then ban the uid and device. Safe to run twice. */
async function eject(authorUid, reportId) {
  if (!authorUid) throw new Error("Report has no author uid");
  const userRef = db.doc(`users/${authorUid}`);
  const user = await userRef.get();
  if (user.exists) {
    await userRef.update({ banned: true });
    const deviceId = user.data().deviceId;
    if (deviceId) {
      await db.doc(`bannedDevices/${deviceId}`).set({ uid: authorUid, reportId, createdAt: new Date() }, { merge: true });
      console.log(`  banned device ${deviceId}`);
    }
  } else {
    console.log("  user document already gone; still writing the ban and deleting content");
  }
  await db.doc(`bans/${authorUid}`).set({ uid: authorUid, banned: true, reportId, createdAt: new Date() }, { merge: true });

  const bottles = await db.collection("bottles").where("senderId", "==", authorUid).get();
  await commitDeletes(bottles.docs);
  console.log(`  deleted ${bottles.size} bottle(s)`);

  const chats = await db.collection("chats").where("participants", "array-contains", authorUid).get();
  let messages = 0;
  for (const chat of chats.docs) {
    const msgs = await chat.ref.collection("messages").where("senderId", "==", authorUid).get();
    await commitDeletes(msgs.docs);
    messages += msgs.size;
    await chat.ref.update({ blocked: true, lastMessage: "" }).catch(() => undefined);
  }
  console.log(`  deleted ${messages} message(s) across ${chats.size} chat(s)`);

  const bucket = admin.storage().bucket();
  await bucket.deleteFiles({ prefix: `bottles/${authorUid}/` }).catch(() => undefined);

  const reports = await db.collection("reports").where("targetUserId", "==", authorUid).get();
  const also = await db.collection("reports").where("authorUid", "==", authorUid).get();
  const ids = new Map();
  for (const d of [...reports.docs, ...also.docs]) ids.set(d.id, d);
  for (const d of ids.values()) {
    if (d.data().status === "dismissed" || d.data().status === "confirmed") continue;
    await d.ref.set({ status: "confirmed", reviewedBy: "cli", reviewedAt: new Date() }, { merge: true });
  }
  console.log(`Banned ${authorUid}. Firestore rules reject throws, replies, and new messages from this uid (bans/${authorUid}).`);
}

async function remove(reportId) {
  const ref = db.doc(`reports/${reportId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("No such report: " + reportId);
  const author = authorOf(snap.data());
  await eject(author, reportId);
  await ref.set({ status: "confirmed", reviewedBy: "cli", reviewedAt: new Date() }, { merge: true });
}

async function dismiss(reportId) {
  const ref = db.doc(`reports/${reportId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("No such report: " + reportId);
  await ref.set({ status: "dismissed", reviewedBy: "cli", reviewedAt: new Date() }, { merge: true });
  console.log("Dismissed " + reportId);
}

async function grantAdmin(uid) {
  await admin.auth().setCustomUserClaims(uid, { admin: true });
  console.log("Granted admin to " + uid + ". That account must sign in again.");
}

(async () => {
  const [cmd, arg] = process.argv.slice(2);
  if (cmd === "list") await list();
  else if ((cmd === "remove" || cmd === "ban") && arg) await remove(arg);
  else if (cmd === "dismiss" && arg) await dismiss(arg);
  else if (cmd === "grant-admin" && arg) await grantAdmin(arg);
  else {
    console.log("Usage: node scripts/moderate.js list | remove <reportId> | dismiss <reportId> | grant-admin <uid>");
    process.exitCode = 1;
  }
})().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
