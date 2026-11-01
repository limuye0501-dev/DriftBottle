# 漂流瓶（DriftBottle）

SwiftUI iOS 17+ 交友漂流瓶应用，后端使用 Firebase（Auth / Firestore / Storage / Messaging / Functions）。

## 在 Mac 上打开
1. 安装 Xcode 15+ 和 XcodeGen：`brew install xcodegen`
2. 在 [Firebase 控制台](https://console.firebase.google.com) 创建项目，添加 iOS 应用（Bundle ID 默认 `com.example.driftbottle`，可在 `project.yml` 中修改）。
3. 下载 `GoogleService-Info.plist`，放到 `DriftBottle/Resources/` 目录。
4. 在 Firebase 中启用 **Apple 登录**、Firestore、Storage、Cloud Messaging（上传 APNs Key）。
5. 在项目根目录执行 `xcodegen generate`，然后打开 `DriftBottle.xcodeproj`。Xcode 会自动通过 SPM 拉取 Firebase。
6. 在 Signing & Capabilities 中选择你的开发团队；确认已有 Sign in with Apple 与 Push Notifications 能力。
7. StoreKit：在 App Store Connect 建立自动续期订阅 `com.example.driftbottle.annual`（¥98/年），或本地新建 StoreKit Configuration 文件测试。

## 部署云函数与规则
```bash
npm i -g firebase-tools && firebase login
cd functions && npm install && npm run build && cd ..
firebase deploy --only functions,firestore:rules
```
Firestore 复合索引：首次运行时控制台会给出创建链接（bottles: recipientId+status+pickCount+createdAt；status+senderGender+senderBirthYear 等）。

## 核心规则
- 仅 Apple 登录，不做手机号/实名认证；昵称、性别、生日在注册时填写，性别与生日不可修改。
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
