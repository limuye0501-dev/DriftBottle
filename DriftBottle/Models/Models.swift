import Foundation
import FirebaseFirestore

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var title: String { self == .male ? "男" : "女" }
    var opposite: Gender { self == .male ? .female : .male }
}

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var nickname: String
    var gender: Gender            // 注册后不可修改（仅服务端可写）
    var age: Int                  // 注册时填写的年龄（不可修改）
    var birthYear: Int            // 服务端按注册时间换算，用于 ±10 岁匹配
    var isMember: Bool = false
    var memberTier: MemberTier? = .free  // 仅服务端写入（syncMembership 校验 JWS 后）
    var memberExpiresAt: Date?
    var blockedUserIds: [String] = []
    var fcmToken: String?
    var createdAt: Date = Date()
    /// 当前年龄 = 当前年份 - 出生年份（随时间自然增长）
    var currentAge: Int { Calendar.current.component(.year, from: Date()) - birthYear }
}

enum BottleStatus: String, Codable {
    case floating          // 已扔出，等待匹配
    case delivered         // 已分配给某位用户，等待被捡
    case viewed            // 被捡起查看
    case kept              // 被保留（准备回复）
    case thrownBack        // 看后放走，继续漂流
    case replied           // 已回复（开启聊天）
    case viewedNoReply     // 看了但超时未回应
    case aiReplied         // 灯塔守望者（AI）回复
    var title: String {
        switch self {
        case .floating: return "漂流中"
        case .delivered: return "正漂向某人"
        case .viewed: return "被真人捡起来看了"
        case .kept: return "被真人保留了，对方正在写回复"
        case .thrownBack: return "被看过后放回了大海，继续漂流中"
        case .replied: return "收到了回复"
        case .viewedNoReply: return "有人看了，但还没有回应"
        case .aiReplied: return "灯塔守望者（AI）回复了你"
        }
    }
}

struct Bottle: Codable, Identifiable {
    @DocumentID var id: String?
    var senderId: String
    var senderNickname: String
    var senderGender: Gender
    var senderBirthYear: Int
    var text: String
    var imageURL: String?
    var imageStatus: String?            // none / pending / approved / blocked（服务端 Vision 审核）
    var style: String? = "classic"      // 年卡专属样式：moonlight / amber / sakura
    var status: BottleStatus = .floating
    var recipientId: String?
    var pickCount: Int = 0
    var thrownBackBy: [String] = []
    var chatId: String?
    var replierIds: [String] = []   // 最多 3 人回复
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var viewedAt: Date?
    /// 图片仅在审核通过后展示（旧数据无该字段视为已通过）
    var visibleImageURL: String? {
        guard let imageURL, imageStatus == nil || imageStatus == "approved" || imageStatus == "none" else { return nil }
        return imageURL
    }
}

struct InAppNotice: Codable, Identifiable {
    @DocumentID var id: String?
    var bottleId: String
    var message: String
    var kind: String = "human"   // human=真人动作 / ai=灯塔守望者（AI）/ system
    var event: String? = "status" // replied = 真人回信（首次收到时展示会员页）
    var read: Bool = false
    var createdAt: Date = Date()
}

struct Chat: Codable, Identifiable {
    @DocumentID var id: String?
    var participants: [String]
    var bottleId: String
    var isAI: Bool = false
    var lastMessage: String = ""
    var blocked: Bool = false
    var names: [String: String] = [:]
    var updatedAt: Date = Date()
}

struct ChatMessage: Codable, Identifiable {
    @DocumentID var id: String?
    var senderId: String       // "ai_lighthouse" 表示 AI
    var text: String
    var imageURL: String?
    var isAI: Bool = false
    var createdAt: Date = Date()
}

/// 会员等级。与 functions/src/appstore.ts 的 PRODUCTS / TIER_QUOTA 保持一致（服务端为准）
enum MemberTier: String, Codable, CaseIterable, Identifiable {
    case free, monthly, annual
    var id: String { rawValue }
    var title: String { switch self { case .free: "免费"; case .monthly: "月卡"; case .annual: "年卡" } }
    /// 每日扔 / 捡次数（各自）；nil = 不限次数（年卡，服务端另有隐藏防刷上限）
    var dailyLimit: Int? { switch self { case .free: 3; case .monthly: 20; case .annual: nil } }
    var rank: Int { switch self { case .free: 0; case .monthly: 1; case .annual: 2 } }
    var quotaText: String { dailyLimit.map { "每天扔 \($0) 次、捡 \($0) 次" } ?? "扔瓶、捡瓶不限次数" }
    var productId: String? {
        switch self { case .free: nil; case .monthly: "com.example.driftbottle.monthly"; case .annual: "com.example.driftbottle.annual" }
    }
    var fallbackPrice: String { switch self { case .free: "¥0"; case .monthly: "¥8"; case .annual: "¥88" } }
    var period: String { self == .monthly ? "月" : "年" }
    var perks: [String] {
        switch self {
        case .free: [quotaText, "保留、回信、聊天、发图永久免费"]
        case .monthly: [quotaText]
        case .annual: ["不限次数：扔瓶、捡瓶都不限", "年卡专属瓶子样式（月光 / 琥珀 / 樱花）"]
        }
    }
    static func from(productId: String) -> MemberTier? { allCases.first { $0.productId == productId } }
}

/// 瓶子样式：classic 所有人可用，其余为年卡专属
enum BottleStyle: String, CaseIterable, Identifiable {
    case classic, moonlight, amber, sakura
    var id: String { rawValue }
    var title: String { switch self { case .classic: "经典"; case .moonlight: "月光"; case .amber: "琥珀"; case .sakura: "樱花" } }
    var exclusive: Bool { self != .classic }
}

enum AppConstants {
    static let freeDailyLimit = 3
    /// 免费试用：默认关闭。仅当在 App Store Connect 配置了介绍性优惠且此开关打开时，付费墙才会展示试用文案
    static let offerFreeTrial = false
    static let maxBottleChars = 200
    static let ageRange = 10
    static let aiSenderId = "ai_lighthouse"
    static let maxRepliers = 3
    static let newAccountDailyThrows = 3
    static let aiName = "灯塔守望者"
    static let firstVisitorText = "你是这片海的第一位访客，灯塔守望者先陪你聊聊"
    static let subscriptionGroup = "漂流瓶会员"   // 订阅组：月卡 + 年卡（占位 ID 见 MemberTier.productId）
    static let firstLaunchHook = "今晚你也睡不着吗？"
}
