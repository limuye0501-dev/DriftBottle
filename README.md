# 漂流瓶（DriftBottle）

SwiftUI iOS 17+ 陌生人漂流瓶应用（匿名进入，无需注册），后端使用 Firebase（Auth / Firestore / Storage / Messaging / Functions）。

## 在 Mac 上打开
1. 安装 Xcode 15+ 和 XcodeGen：`brew install xcodegen`
2. 在 [Firebase 控制台](https://console.firebase.google.com) 创建项目，添加 iOS 应用（Bundle ID 默认 `com.example.driftbottle`，可在 `project.yml` 中修改）。
3. 下载 `GoogleService-Info.plist`，放到 `DriftBottle/Resources/` 目录。
4. 在 Firebase Authentication 中启用 **匿名登录（Anonymous）**，并启用 Firestore、Storage、Cloud Messaging（上传 APNs Key）。
5. 在项目根目录执行 `xcodegen generate`，然后打开 `DriftBottle.xcodeproj`。Xcode 会自动通过 SPM 拉取 Firebase。
6. 在 Signing & Capabilities 中选择你的开发团队；确认已有 Push Notifications 能力。
7. StoreKit：在 App Store Connect 建立自动续期订阅 `com.example.driftbottle.annual`（¥98/年），或本地新建 StoreKit Configuration 文件测试。

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
- 只能捡到异性、年龄差 ±10 岁的瓶子；免费用户每天扔 8 次、捡 8 次，年度会员每天各 30 次。
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
- **会员**：付费页明确价格、权益、自动续期与取消方式；`syncMembership` 使用 `@apple/app-store-server-library` 校验 StoreKit 2 交易 JWS。
  需配置环境变量 `APPLE_BUNDLE_ID`、`APPLE_APP_ID`、`APPLE_ENV`，并将 Apple 根证书 `AppleRootCA-G3.cer` 放到 `functions/certs/`。
- **新用户触发器**：用户资料创建后，自动把漂流中且符合条件的瓶子分配给 TA。

部署：`firebase deploy --only functions,firestore:rules,storage`

> ⚠️ 仓库是公开的：不要提交 `GoogleService-Info.plist`、API Key、App Store 私钥等任何密钥。

## 机型适配
- 仅支持 iPhone（`TARGETED_DEVICE_FAMILY = 1`）、仅竖屏；最低 iOS 17（iPhone 13 出厂 iOS 15，可升级到 iOS 17）。
- 适配 iPhone 13 mini（375×812）到 16/17 Pro Max（440×956）：海面、沙滩、月亮、按钮与动画轨迹都按屏幕比例计算（`SeaLayout`），内容布局在安全区内，避开刘海/灵动岛。
- 支持动态字体到辅助功能大字号：首页按钮在大字号时改为上下排列并自动增高。
