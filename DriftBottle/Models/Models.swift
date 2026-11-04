import Foundation
import FirebaseFirestore

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var title: String { self == .male ? L("gender.male") : L("gender.female") }
}

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var nickname: String
    var gender: Gender            // 注册后不可修改（仅服务端可写）
    var age: Int                  // 注册时填写的年龄（不可修改）
    var birthYear: Int            // 服务端按注册时间换算，用于显示年龄（匹配不限性别/年龄）
    var isMember: Bool = false
    var memberTier: MemberTier? = .free  // 仅服务端写入（syncMembership 校验 JWS 后）
    var memberExpiresAt: Date?
    var blockedUserIds: [String] = []
    var fcmToken: String?
    var locale: String?           // 客户端界面语言，服务端据此本地化推送/通知
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
    case aiReplied         // 旧数据（AI 已下线）：按“漂流中”展示
    var title: String {
        switch self {
        case .floating: return L("status.floating")
        case .delivered: return L("status.delivered")
        case .viewed: return L("status.viewed")
        case .kept: return L("status.kept")
        case .thrownBack: return L("status.thrownBack")
        case .replied: return L("status.replied")
        case .viewedNoReply: return L("status.viewedNoReply")
        case .aiReplied: return L("status.floating")
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
    var style: String? = "classic"      // 信纸样式：classic / moonlight / amber / sakura（全部免费）
    var font: String?                   // 字体：standard / kai / hand / typewriter（旧数据为空 → 默认）
    var fontSize: String?               // 字号：small / medium / large（旧数据为空 → medium）
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
    var kind: String = "human"   // human=真人动作 / system（旧数据可能为 ai，客户端隐藏）
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
    var senderId: String
    var text: String
    var imageURL: String?
    var isAI: Bool = false
    var hidden: Bool?          // 服务端审核隐藏（文本被清空，客户端显示本地化提示）
    var kind: String?          // "origin" = 对话源自的瓶子原文（客户端用本地化 chat.origin 展示）
    var createdAt: Date = Date()

    /// 旧数据用中文前缀「【瓶子】」标记；新数据用 kind == "origin"
    static let legacyOriginPrefix = "【瓶子】"
    var isOrigin: Bool { kind == "origin" || text.hasPrefix(Self.legacyOriginPrefix) }
    var originText: String { text.hasPrefix(Self.legacyOriginPrefix) ? String(text.dropFirst(Self.legacyOriginPrefix.count)) : text }
}

/// 会员等级。与 functions/src/appstore.ts 的 PRODUCTS / TIER_QUOTA 保持一致（服务端为准）
enum MemberTier: String, Codable, CaseIterable, Identifiable {
    case free, monthly, annual
    var id: String { rawValue }
    var title: String { switch self { case .free: L("tier.free"); case .monthly: L("tier.monthly"); case .annual: L("tier.annual") } }
    /// 每日扔 / 捡次数（各自）；nil = 不限次数（年卡，服务端另有隐藏防刷上限）
    var dailyLimit: Int? { switch self { case .free: 3; case .monthly: 20; case .annual: nil } }
    var rank: Int { switch self { case .free: 0; case .monthly: 1; case .annual: 2 } }
    var quotaText: String { dailyLimit.map { L("tier.quota", $0) } ?? L("tier.quota.unlimited") }
    var productId: String? {
        switch self { case .free: nil; case .monthly: "com.limuye.driftbottle.monthly"; case .annual: "com.limuye.driftbottle.annual" }
    }
    /// 价格一律来自 StoreKit displayPrice（按用户所在店面货币）；商品未加载时显示占位
    var fallbackPrice: String { "—" }
    /// 「价格/周期」，如 "¥88/年"、"$12.99/year"
    func pricePerPeriod(_ price: String) -> String { self == .monthly ? L("price.per_month", price) : L("price.per_year", price) }
    var perks: [String] {
        switch self {
        case .free: [quotaText, L("perk.free_core")]
        case .monthly: [quotaText]
        case .annual: [L("perk.unlimited")]
        }
    }
    static func from(productId: String) -> MemberTier? { allCases.first { $0.productId == productId } }
}

/// 瓶子样式 / 信纸：所有样式对所有人免费
enum BottleStyle: String, CaseIterable, Identifiable {
    case classic, moonlight, amber, sakura
    var id: String { rawValue }
    var title: String { switch self { case .classic: L("style.classic"); case .moonlight: L("style.moonlight"); case .amber: L("style.amber"); case .sakura: L("style.sakura") } }
}

enum AppConstants {
    static let freeDailyLimit = 3
    /// 免费试用：默认关闭。仅当在 App Store Connect 配置了介绍性优惠且此开关打开时，付费墙才会展示试用文案
    static let offerFreeTrial = false
    static let maxBottleChars = 200
    static let ageRange = 10
    static let maxRepliers = 3
    static let newAccountDailyThrows = 3
    static let subscriptionGroup = "漂流瓶会员"   // 订阅组：月卡 + 年卡（占位 ID 见 MemberTier.productId）
    static var firstLaunchHook: String { L("hook.first_launch") }
}

/// 信件字体（随瓶子保存，捡到的人按同样字体显示；旧瓶子为空 → standard）
enum LetterFont: String, CaseIterable, Identifiable {
    case standard, kai, hand, typewriter
    var id: String { rawValue }
    var title: String {
        switch self { case .standard: L("font.standard"); case .kai: L("font.kai"); case .hand: L("font.hand"); case .typewriter: L("font.typewriter") }
    }
    init(stored: String?) { self = stored.flatMap(LetterFont.init(rawValue:)) ?? .standard }
}

/// 信件字号
enum LetterSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { switch self { case .small: L("size.small"); case .medium: L("size.medium"); case .large: L("size.large") } }
    init(stored: String?) { self = stored.flatMap(LetterSize.init(rawValue:)) ?? .medium }
}
