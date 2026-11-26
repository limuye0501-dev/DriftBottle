# Moderation

Drift Bottle has zero tolerance for objectionable content and abusive users. Review every open report within 24 hours. Remove the content and eject the user who posted it.

Support email shown in the app: limuye0501@gmail.com

## What the app already does

- A report writes `reports/{id}` with `bottleId`, `authorUid`, `reporterId`, `reason`, and `createdAt`.
- The bottle disappears from the reporter's sea immediately.
- Two different people reporting the same bottle sets `hidden` and takes it out of the pool (`onReportCreated`). Two reports of the same reply hide that message.
- Blocking writes `users/{uid}.blockedUserIds` and `users/{uid}/blocks/{other}`. Blocked users' bottles are not delivered again.
- Confirming a report (`status: confirmed`) runs `onReportConfirmed`, which deletes the author's bottles and messages, sets `users.banned`, writes `bans/{uid}`, and bans the device.

## 24-hour backstop (deployed)

`moderationSweep` is a scheduled Cloud Function that runs every hour. Any report still `pending` after 20 hours has its bottle or message hidden from everyone (`hiddenReason: report_timeout`), so reported content is always gone within 24 hours even if nobody looked at it. The report stays `pending` with `autoHiddenAt` set, so it still shows in `moderate.js list` for the ban decision. Each run logs `MODERATION_SWEEP` with the pending count and how much it hid:

```bash
npx firebase-tools functions:log --only moderationSweep --project driftbottle-706bb
```

Firestore rules also stop a recipient from reading a bottle once it is `hidden`.

Cloud Logging records each new report as `REPORT_REVIEW_REQUIRED`. You can turn that log into an email alert in Google Cloud so a new report pages you. The queue itself is the `reports` collection. This script is the way to clear it inside 24 hours even if the alert is not set up.

## Act on a report

From a machine that can use the Firebase Admin SDK. Do not commit credentials.

```bash
gcloud auth application-default login
cd tools/admin && npm install
node ../../scripts/moderate.js list
node ../../scripts/moderate.js remove <reportId>
node ../../scripts/moderate.js dismiss <reportId>
```

`remove` (alias `ban`):

1. Deletes every bottle whose `senderId` is the author, so it leaves the sea immediately.
2. Deletes that uid's chat messages and closes those chats.
3. Sets `users/{uid}.banned` to true and writes `bans/{uid}`.
4. If the account has a device id, writes `bannedDevices/{deviceId}`.
5. Marks this report and the author's other open reports `confirmed`.

`tools/admin/admin.js list|ban|dismiss` forwards here. `ban` means `remove`. `node admin.js grant-admin <uid>` is unchanged.

The project id is `FIREBASE_PROJECT` or the default in `.firebaserc` (`driftbottle-706bb`).

## Why a banned user cannot post

Firestore rules reject the banned uid:

- `bans/{uid}` exists, or `users/{uid}.banned` is true.
- They cannot create chat messages, file reports, block, delete, or hide a bottle.
- Throwing and replying go through Cloud Functions (`throwBottle`, `replyBottle`). `getUser` rejects a banned uid or a banned device before a bottle or reply is written.

Deleting the app does not clear `bannedDevices`. A new anonymous account on that device is banned again when it registers.
