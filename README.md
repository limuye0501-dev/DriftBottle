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
