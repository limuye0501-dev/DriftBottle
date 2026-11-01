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

## 部署云函数与规则
```bash
npm i -g firebase-tools && firebase login
cd functions && npm install && npm run build && cd ..
firebase deploy --only functions,firestore:rules
```
Firestore 复合索引：首次运行时控制台会给出创建链接（bottles: recipientId+status+pickCount+createdAt；status+senderGender+senderBirthYear 等）。

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
| 免费 | — | 5 / 5 | 回信、聊天、发图、举报拉黑永久免费 |
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
