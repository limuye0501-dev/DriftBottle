# 漂流瓶（DriftBottle）

SwiftUI iOS 17+ 陌生人漂流瓶应用（匿名进入，无需注册），后端使用 Firebase（Auth / Firestore / Storage / Messaging / Functions）。

## 在 Mac 上打开
1. 安装 Xcode 15+ 和 XcodeGen：`brew install xcodegen`
2. 在 [Firebase 控制台](https://console.firebase.google.com) 创建项目，添加 iOS 应用（Bundle ID 默认 `com.example.driftbottle`，可在 `project.yml` 中修改）。
3. 下载 `GoogleService-Info.plist`，放到 `DriftBottle/Resources/` 目录。
4. 在 Firebase Authentication 中启用 **匿名登录（Anonymous）**，并启用 Firestore、Storage、Cloud Messaging（上传 APNs Key）。
5. 在项目根目录执行 `xcodegen generate`，然后打开 `DriftBottle.xcodeproj`。Xcode 会自动通过 SPM 拉取 Firebase。
6. 在 Signing & Capabilities 中选择你的开发团队；确认已有 Push Notifications 能力。
7. StoreKit：在 App Store Connect 建立订阅组「漂流瓶会员」，内含 2 个自动续期订阅（占位 ID）：`com.example.driftbottle.monthly`（月卡 ¥8/月）、`com.example.driftbottle.annual`（年卡 ¥88/年）。不设免费试用（`AppConstants.offerFreeTrial` 默认 false）。

## 上线前配置清单（新手版）

按顺序做，每一步做完打个勾即可。**任何密钥、.p8 文件、GoogleService-Info.plist 都不要提交到仓库**（已在 .gitignore 中忽略）。

### A. Firebase 项目
- [ ] 把 `.firebaserc` 里的 `your-firebase-project-id` 改成你的 Firebase 项目 ID（控制台 → 项目设置 → 项目 ID）。
- [ ] 项目升级到 **Blaze（按量付费）** 方案（云函数、Vision、Secret Manager 需要；小规模基本在免费额度内）。
- [ ] Authentication → 登录方式 → 启用 **匿名**。
- [ ] Firestore、Storage 都创建好（区域建议 `asia-east2` 香港，与云函数一致）。
- [ ] 安装工具并部署：
  ```bash
  npm i -g firebase-tools && firebase login
  cd functions && npm install && cp .env.example .env   # 编辑 .env 填 Bundle ID / App ID / 环境
  cd .. && firebase deploy --only functions,firestore,storage
  ```
  `firebase deploy --only firestore` 会同时上传规则和 `firestore.indexes.json` 里的全部复合索引（建好需几分钟）。

### B. 推送（APNs → FCM）
- [ ] Apple Developer → Certificates, IDs & Profiles → Keys → 新建 Key，勾选 **Apple Push Notifications service (APNs)**，下载 `.p8`（只能下载一次，妥善保存）。
- [ ] Firebase 控制台 → 项目设置 → Cloud Messaging → Apple 应用配置 → 上传这个 `.p8`，填 Key ID 和 Team ID。
- [ ] Xcode → Signing & Capabilities 确认有 **Push Notifications** 和 **Background Modes → Remote notifications**（`project.yml` 已配置）。
- 推送文案为中文；每人每小时最多 8 条、同一聊天 2 分钟内只推 1 条，北京时间 23:00–08:00 静音送达。

### C. 图片审核（Cloud Vision）
- [ ] 打开 [Google Cloud 控制台](https://console.cloud.google.com) → 选同一个项目 → API 库 → 启用 **Cloud Vision API**。无需密钥，云函数用默认服务账号调用。
- 策略偏宽松：只拦截“很可能/极可能”的色情或暴力，以及“极可能”的过度暴露；被拦截的图片会被删除、瓶子不漂出并通知发送者。图片审核通过前瓶子不会投递。

### D. App Store 订阅与服务器通知
- [ ] App Store Connect → 你的 App → 订阅：建好订阅组和两个商品（ID 见上文第 7 步）。
- [ ] App Store Connect → 用户和访问 → 集成 → **App 内购买项目** → 生成 In-App Purchase Key，记下 **Key ID**、**Issuer ID**，下载 `.p8`。然后：
  ```bash
  firebase functions:secrets:set APPLE_IAP_KEY        # 粘贴 .p8 文件全部内容
  firebase functions:secrets:set APPLE_IAP_KEY_ID
  firebase functions:secrets:set APPLE_IAP_ISSUER_ID
  ```
- [ ] `functions/.env` 填：`APPLE_BUNDLE_ID`、`APPLE_APP_ID`（App Store Connect → App 信息 → Apple ID 数字）、`APPLE_ENV`（测试用 `Sandbox`，上架后改 `Production` 并重新部署）。
- [ ] 下载 Apple 根证书 [AppleRootCA-G3.cer](https://www.apple.com/certificateauthority/AppleRootCA-G3.cer) 放到 `functions/certs/`（公开证书，可提交）。
- [ ] 部署后，在 Firebase 控制台 → Functions 找到 `appStoreNotifications` 的网址；App Store Connect → App 信息 → **App Store 服务器通知** → 生产和沙盒都填这个网址，版本选 **V2**，点“发送测试通知”，日志里看到“App Store 测试通知 OK”即成功。
- 处理的通知：SUBSCRIBED / DID_RENEW / EXPIRED / REFUND / REVOKE / DID_CHANGE_RENEWAL_STATUS（以及 GRACE_PERIOD_EXPIRED、REFUND_REVERSED、OFFER_REDEEMED），会员等级和到期时间实时更新。
- **退款**：付费页注明“虚拟服务，开通后即时生效，不支持退款”，条款说明退款由 Apple 依据其政策处理。Apple 发来 CONSUMPTION_REQUEST 时，仅在用户于付费页勾选同意后，服务端回传使用情况（扔/捡次数、已交付、倾向不退款）；最终是否退款由 Apple 决定，退款成功会自动取消会员。

### E. 举报审核（管理员）
- [ ] 本机登录 Google Cloud：`gcloud auth application-default login`（或设置 `GOOGLE_APPLICATION_CREDENTIALS` 指向服务账号 JSON，**不要提交**）。
- [ ] `cd tools/admin && npm install`
- `node admin.js list` 查看待处理举报；`node admin.js ban <举报ID>` 封禁被举报账号和设备；`node admin.js dismiss <举报ID>` 驳回。
- 想在 App 或其他客户端调用云函数 `reviewReport`：先 `node admin.js grant-admin <你的 uid>`，重新登录后生效。

## 核心规则
- 首次打开自动匿名登录（Firebase Anonymous Auth），不收集手机号、姓名、邮箱。
- 引导页只填性别 + 年龄（须 18 岁以上）；昵称自动生成（如“漂流者0427”），可修改。性别和年龄提交后不可修改，服务端按注册时间换算出生年份用于 ±10 岁匹配。
- 资料由云函数 `createProfile` 创建；新账号 24 小时限制、每日配额和封禁都按设备（identifierForVendor）计算，卸载重装不会重置。
- 注意：匿名账号只存在本机，卸载重装后会以新身份进入，旧聊天无法找回。
- 只能捡到异性、年龄差 ±10 岁的瓶子；新账号首 24 小时每天最多扔 3 个。
- 只要存在符合条件的真实用户，瓶子一定会被投递给真实用户（扔回后继续投递下一位，未被捡过的优先）。
- 发送者会收到状态通知：被捡起、被扔回大海、已回复、看了但超时未回应。
- 「灯塔守望者」是明确标注的 AI，只在没有其他符合条件的真实用户时（如第一位用户）回复，绝不冒充真人。

## 第二批新增
- **聊天**：会话列表 + 实时聊天（文字/图片），AI 消息始终带「AI」标签；聊天内可举报/拉黑。基础聊天与回复永久免费。
- **保留才能聊**：捡到瓶子后选择「保留」才能回复，或「放走」让它继续漂流；每个瓶子最多 3 人回复。
- **内容预审**（`functions/src/moderation.ts`）：色情/违规关键词 + 微信/QQ/手机号/二维码/链接等引流正则（含全角、中文数字等变形）；设置 `MODERATION_API_URL`、`MODERATION_API_KEY`（Secret Manager）即可接入第三方审核 API（图片二维码/色情识别依赖该 API）。
- **新账号限流**：注册 24 小时内每天最多扔 3 个瓶子。
- **设备封禁**：App 上报 `identifierForVendor`；管理员把 `reports/{id}.status` 改为 `confirmed` 后，账号与设备均被封禁。
- **通知区分**：真人动作 vs 灯塔守望者（AI）。
- **会员**：付费页明确价格、权益、自动续期与取消方式；`syncMembership` 使用 `@apple/app-store-server-library` 校验 StoreKit 2 交易 JWS，按商品 ID 映射等级（`functions/src/appstore.ts` 的 `PRODUCTS` / `TIER_QUOTA`），写入 `users.memberTier`（客户端不可写）。
- **付费墙只在三种情况出现**：首次收到真人回信（只一次）、当日额度用完、用户手动进入（首页链接 / 我 / 专属样式）。
  需配置环境变量 `APPLE_BUNDLE_ID`、`APPLE_APP_ID`、`APPLE_ENV`，并将 Apple 根证书 `AppleRootCA-G3.cer` 放到 `functions/certs/`。
- **新用户触发器**：用户资料创建后，自动把漂流中且符合条件的瓶子分配给 TA。

部署：`firebase deploy --only functions,firestore:rules,storage`

> ⚠️ 仓库是公开的：不要提交 `GoogleService-Info.plist`、API Key、App Store 私钥等任何密钥。

## 机型适配
- 仅支持 iPhone（`TARGETED_DEVICE_FAMILY = 1`）、仅竖屏；最低 iOS 17（iPhone 13 出厂 iOS 15，可升级到 iOS 17）。
- 适配 iPhone 13 mini（375×812）到 16/17 Pro Max（440×956）：海面、沙滩、月亮、按钮与动画轨迹都按屏幕比例计算（`SeaLayout`），内容布局在安全区内，避开刘海/灵动岛。
- 支持动态字体到辅助功能大字号：首页按钮在大字号时改为上下排列并自动增高。


## 会员等级
| 等级 | 价格 | 每日扔 / 捡 | 其他 |
|---|---|---|---|
| 免费 | — | 3 / 3 | 回信、聊天、发图、举报拉黑永久免费 |
| 月卡 | ¥8/月 | 20 / 20 | |
| 年卡 | ¥88/年 | 不限次数 | 年卡专属瓶子样式（月光 / 琥珀 / 樱花） |

年卡在界面上显示「不限次数」；服务端保留隐藏的防刷上限 200 次/天（`ANNUAL_ABUSE_CAP`），并照常执行内容审核与新账号限制。

## v2 视觉
- 设计令牌：`DriftBottle/Theme/Theme.swift`（#070B1A / #0E1630 / 文字 #F3E9D2 / 琥珀 #F5B85A；正文 PingFang SC 跟随动态字体，信件衬线体；系统材质 + SF Symbols）。
- 首页：天空随本地时间变化（黄昏 / 入夜 / 深夜 / 黎明 / 白天）、灯塔光束每 8 秒扫一圈、萤火虫；保留原有海浪与扔 / 捡动画。开启「减弱动态效果」时全部静止。
- 首次启动钩子：「今晚你也睡不着吗？」，只出现一次。
- App 图标：`Assets.xcassets/AppIcon.appiconset`（1024 单尺寸）。

## 需要的音效
已提供，位于 `DriftBottle/Resources/Sounds/`（原创程序化合成，CC0，无需署名；来源与许可见该目录 `LICENSES.md`，生成脚本 `tools/sfx/gen.py`）。替换时文件名（不含扩展名）需一致，.m4a 或 .caf 均可；缺失时静默跳过，跟随静音键：
| 文件名 | 用途 |
|---|---|
| sfx_waves_loop | 首页海浪环境音（无缝循环，30–60 秒） |
| sfx_throw_whoosh | 扔瓶出手 |
| sfx_splash | 瓶子入水 |
| sfx_net_dip | 网兜入水 |
| sfx_pick_up | 捞起瓶子 |
| sfx_cork_pop | 拔瓶塞 |
| sfx_paper_unfold | 展开信纸 |
| sfx_send | 发送消息 / 回信 |
| sfx_receive | 收到消息 / 通知 |
| sfx_lighthouse_chime | 首次收到真人回信 |
