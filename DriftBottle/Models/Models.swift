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
    var gender: Gender            // 注册后不可修改（Firestore 规则同样限制）
    var birthday: Date            // 注册后不可修改
    var birthYear: Int
    var isMember: Bool = false
    var memberExpiresAt: Date?
    var blockedUserIds: [String] = []
    var fcmToken: String?
    var createdAt: Date = Date()
    var age: Int { Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0 }
}

enum BottleStatus: String, Codable {
    case floating          // 已扔出，等待匹配
    case delivered         // 已分配给某位用户，等待被捡
    case viewed            // 被捡起查看
    case thrownBack        // 看后扔回大海
    case replied           // 已回复（开启聊天）
    case viewedNoReply     // 看了但超时未回应
    case aiReplied         // 灯塔守望者（AI）回复
    var title: String {
        switch self {
        case .floating: return "漂流中"
        case .delivered: return "正漂向某人"
        case .viewed: return "被捡起来看了"
        case .thrownBack: return "被看过后扔回了大海"
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
    var status: BottleStatus = .floating
    var recipientId: String?
    var pickCount: Int = 0
    var thrownBackBy: [String] = []
    var chatId: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var viewedAt: Date?
}

struct InAppNotice: Codable, Identifiable {
    @DocumentID var id: String?
    var bottleId: String
    var message: String
    var read: Bool = false
    var createdAt: Date = Date()
}

struct Chat: Codable, Identifiable {
    @DocumentID var id: String?
    var participants: [String]
    var bottleId: String
    var isAI: Bool = false
    var lastMessage: String = ""
    var updatedAt: Date = Date()
}

struct ChatMessage: Codable, Identifiable {
    @DocumentID var id: String?
    var senderId: String       // "ai_lighthouse" 表示 AI
    var text: String
    var isAI: Bool = false
    var createdAt: Date = Date()
}

enum AppConstants {
    static let freeDailyLimit = 8
    static let memberDailyLimit = 30
    static let maxBottleChars = 200
    static let ageRange = 10
    static let aiSenderId = "ai_lighthouse"
    static let aiName = "灯塔守望者"
    static let firstVisitorText = "你是这片海的第一位访客，灯塔守望者先陪你聊聊"
    static let annualProductId = "com.example.driftbottle.annual" // 占位，¥98/年
}
