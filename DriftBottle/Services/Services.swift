import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions
import FirebaseMessaging
import UIKit
import StoreKit

let db = Firestore.firestore()

// MARK: - Session / Sign in with Apple
@MainActor
final class SessionStore: ObservableObject {
    enum State { case loading, signedOut, needsOnboarding, ready }
    @Published var state: State = .loading
    @Published var profile: UserProfile?
    @Published var error: String?
    private var nonce: String?
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { await self?.refresh(user: user) }
        }
    }
    var uid: String? { Auth.auth().currentUser?.uid }

    func refresh(user: User?) async {
        guard let user else { state = .signedOut; profile = nil; return }
        profile = try? await UserService.shared.fetch(uid: user.uid)
        state = profile == nil ? .needsOnboarding : .ready
        if profile != nil { await DeviceIdentity.register() }
    }

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let n = Self.randomNonce(); nonce = n
        request.requestedScopes = []   // 不收集真实姓名/邮箱
        request.nonce = Self.sha256(n)
    }
    func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let e): error = "登录失败：\(e.localizedDescription)"
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let nonce else { error = "登录凭证无效"; return }
            let c = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: nil)
            do { _ = try await Auth.auth().signIn(with: c) } catch { self.error = "登录失败：\(error.localizedDescription)" }
        }
    }
    func completeOnboarding(nickname: String, gender: Gender, birthday: Date) async {
        guard let uid else { return }
        let p = UserProfile(id: uid, nickname: nickname, gender: gender, birthday: birthday,
                            birthYear: Calendar.current.component(.year, from: birthday))
        do { try await UserService.shared.create(p, uid: uid); await DeviceIdentity.register(); profile = p; state = .ready }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    func signOut() { try? Auth.auth().signOut() }
    func deleteAccount() async {
        // 注：Apple 要求撤销 token；完整实现需重新认证并调用 Auth.revokeToken(withAuthorizationCode:)
        do {
            _ = try await Functions.functions().httpsCallable("deleteAccount").call()
            try await Auth.auth().currentUser?.delete()
        } catch { self.error = "注销失败，请重新登录后再试：\(error.localizedDescription)" }
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Users
final class UserService {
    static let shared = UserService()
    func fetch(uid: String) async throws -> UserProfile? {
        let doc = try await db.collection("users").document(uid).getDocument()
        return doc.exists ? try doc.data(as: UserProfile.self) : nil
    }
    func create(_ p: UserProfile, uid: String) async throws {
        try db.collection("users").document(uid).setData(from: p)
    }
    func updateFCMToken(_ t: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid).setData(["fcmToken": t], merge: true)
    }
    func block(_ otherId: String) async throws {
        _ = try await Functions.functions(region: "asia-east2").httpsCallable("blockUser").call(["targetUserId": otherId])
    }
    func report(targetUserId: String, bottleId: String?, reason: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("reports").addDocument(data: ["reporterId": uid, "targetUserId": targetUserId,
            "bottleId": bottleId ?? "", "reason": reason, "createdAt": FieldValue.serverTimestamp()])
    }
}

// MARK: - Quota（客户端展示；真正校验在 Cloud Function）
struct QuotaService {
    static func dayKey(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = TimeZone(identifier: "Asia/Shanghai"); return f.string(from: d)
    }
    static func limit(isMember: Bool) -> Int { isMember ? AppConstants.memberDailyLimit : AppConstants.freeDailyLimit }
    static func usage(uid: String) async -> (throws: Int, picks: Int) {
        let d = try? await db.collection("users").document(uid).collection("quota").document(dayKey()).getDocument()
        return (d?.data()?["throws"] as? Int ?? 0, d?.data()?["picks"] as? Int ?? 0)
    }
}

// MARK: - Sensitive words（与 functions/src/moderation.ts 保持一致；服务端为准）
enum SensitiveWordFilter {
    static let words = ["色情", "裸聊", "约炮", "一夜情", "援交", "包养", "黄片", "成人视频",
                        "赌博", "博彩", "代孕", "毒品", "冰毒", "枪支", "刷单", "加微信转账"]
    private static let kw = "(?:微信|威信|薇信|徽信|v信|vx|wx|weixin|wechat|加v|\\+v|qq|扣扣|企鹅|球球|telegram|tg|whatsapp|line|ins|抖音号?|小红书号?|手机号?|电话|加我|联系我|私聊我|扫码|二维码)"
    private static let handle = "(?:(?=[a-z0-9_-]*\\d)[a-z][a-z0-9_-]{5,19}|\\d{5,})"
    private static let patterns: [String] = [
        kw + "[\\s:：号是为=\\-~]{0,4}" + handle,          // 关键词 + 账号
        handle + "[\\s,，]{0,2}(?:是我的?)?" + kw,            // 账号 + 关键词
        "(?<!\\d)\\d{7,}(?!\\d)",                          // 7 位以上数字（手机号/QQ）
        "(https?://|www\\.|t\\.me/|[a-z0-9-]+\\.(com|cn|net|top|xyz|io|me)\\b)" // 链接
    ]
    /// 规整全角、零宽字符、中文数字、数字间分隔符
    static func normalize(_ s: String) -> String {
        let cn: [Character: Character] = ["零":"0","〇":"0","一":"1","壹":"1","二":"2","贰":"2","三":"3","叁":"3","四":"4","肆":"4",
                                          "五":"5","伍":"5","六":"6","陆":"6","七":"7","柒":"7","八":"8","捌":"8","九":"9","玖":"9"]
        var out = (s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s)
            .replacingOccurrences(of: "[\\u200B-\\u200D\\uFEFF]", with: "", options: .regularExpression)
        out = String(out.map { cn[$0] ?? $0 })
        out = out.replacingOccurrences(of: "(\\d)[\\s.\\-_·•]+(?=\\d)", with: "$1", options: .regularExpression)
        return out.lowercased()
    }
    static func contains(_ raw: String) -> Bool {
        let s = normalize(raw)
        if words.contains(where: { s.contains($0) }) { return true }
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }
}

enum ImageCompressor {
    static func compress(_ img: UIImage, maxSide: CGFloat = 1080, quality: CGFloat = 0.6) -> Data? {
        let s = img.size, scale = min(1, maxSide / max(s.width, s.height))
        let size = CGSize(width: s.width * scale, height: s.height * scale)
        let r = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return r.jpegData(compressionQuality: quality)
    }
}

// MARK: - Bottles（匹配逻辑在 Cloud Functions）
enum BottleError: LocalizedError {
    case sensitive, tooLong, empty, server(String)
    var errorDescription: String? {
        switch self {
        case .sensitive: return "内容包含敏感词，请修改后再扔"
        case .tooLong: return "瓶子里最多写 200 字"
        case .empty: return "写点什么再扔吧"
        case .server(let m): return m
        }
    }
}

struct PickResult { let bottle: Bottle?; let isAIFirstVisitor: Bool; let message: String? }

final class BottleService {
    static let shared = BottleService()
    private let fn = Functions.functions(region: "asia-east2")

    func throwBottle(text: String, image: UIImage?) async throws -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw BottleError.empty }
        guard t.count <= AppConstants.maxBottleChars else { throw BottleError.tooLong }
        guard !SensitiveWordFilter.contains(t) else { throw BottleError.sensitive }
        var url: String?
        if let image, let data = ImageCompressor.compress(image), let uid = Auth.auth().currentUser?.uid {
            let ref = Storage.storage().reference().child("bottles/\(uid)/\(UUID().uuidString).jpg")
            _ = try await ref.putDataAsync(data, metadata: { let m = StorageMetadata(); m.contentType = "image/jpeg"; return m }())
            url = try await ref.downloadURL().absoluteString
        }
        let res = try await fn.httpsCallable("throwBottle").call(["text": t, "imageURL": url as Any])
        let d = res.data as? [String: Any] ?? [:]
        if let err = d["error"] as? String { throw BottleError.server(err) }
        if (d["ai"] as? Bool) == true { return d["message"] as? String ?? AppConstants.firstVisitorText }
        return d["message"] as? String ?? "瓶子已经漂向大海"
    }

    func pickBottle() async throws -> PickResult {
        let res = try await fn.httpsCallable("pickBottle").call()
        let d = res.data as? [String: Any] ?? [:]
        if let err = d["error"] as? String { throw BottleError.server(err) }
        if (d["firstVisitor"] as? Bool) == true { return PickResult(bottle: nil, isAIFirstVisitor: true, message: AppConstants.firstVisitorText) }
        guard let id = d["bottleId"] as? String else { return PickResult(bottle: nil, isAIFirstVisitor: false, message: d["message"] as? String ?? "海面上暂时没有瓶子") }
        let b = try await db.collection("bottles").document(id).getDocument(as: Bottle.self)
        return PickResult(bottle: b, isAIFirstVisitor: false, message: nil)
    }

    /// 放走：瓶子继续漂向下一位真人
    func release(_ id: String) async throws { _ = try await fn.httpsCallable("releaseBottle").call(["bottleId": id]) }
    /// 保留：保留后才能回复；每个瓶子最多 3 人回复
    func keep(_ id: String) async throws {
        let r = try await fn.httpsCallable("keepBottle").call(["bottleId": id])
        if let e = (r.data as? [String: Any])?["error"] as? String { throw BottleError.server(e) }
    }
    func reply(_ id: String, text: String) async throws -> String? {
        guard !SensitiveWordFilter.contains(text) else { throw BottleError.sensitive }
        let r = try await fn.httpsCallable("replyBottle").call(["bottleId": id, "text": text])
        let d = r.data as? [String: Any] ?? [:]
        if let e = d["error"] as? String { throw BottleError.server(e) }
        return d["chatId"] as? String
    }

    func listenMyBottles(uid: String, onChange: @escaping ([Bottle]) -> Void) -> ListenerRegistration {
        db.collection("bottles").whereField("senderId", isEqualTo: uid).order(by: "createdAt", descending: true)
            .addSnapshotListener { snap, _ in onChange(snap?.documents.compactMap { try? $0.data(as: Bottle.self) } ?? []) }
    }
    func listenNotices(uid: String, onChange: @escaping ([InAppNotice]) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid).collection("notices").whereField("read", isEqualTo: false)
            .addSnapshotListener { snap, _ in onChange(snap?.documents.compactMap { try? $0.data(as: InAppNotice.self) } ?? []) }
    }
    func markRead(uid: String, noticeId: String) {
        db.collection("users").document(uid).collection("notices").document(noticeId).updateData(["read": true])
    }
}

// MARK: - StoreKit 2 年度会员
@MainActor
final class StoreService: ObservableObject {
    @Published var product: Product?
    @Published var isMember = false
    private var updates: Task<Void, Never>?
    init() {
        updates = Task { for await r in Transaction.updates { if case .verified(let t) = r { await t.finish(); await refresh() } } }
        Task { await load(); await refresh() }
    }
    func load() async { product = try? await Product.products(for: [AppConstants.annualProductId]).first }
    var priceText: String { product?.displayPrice ?? "¥98" }
    @Published var lastError: String?
    func purchase() async throws {
        guard let product else { throw BottleError.server("商品信息加载失败，请稍后重试") }
        let token = UUID(uuidString: Auth.auth().currentUser?.uid.uuidLike ?? "") // appAccountToken 绑定账号
        var opts: Set<Product.PurchaseOption> = []
        if let token { opts.insert(.appAccountToken(token)) }
        switch try await product.purchase(options: opts) {
        case .success(let v):
            if case .verified(let t) = v { await t.finish() }
            await sync(jws: v.jwsRepresentation)
        case .pending: lastError = "购买待确认"
        default: break
        }
    }
    func refresh() async {
        var jws: String?
        for await r in Transaction.currentEntitlements {
            if case .verified(let t) = r, t.productID == AppConstants.annualProductId, t.revocationDate == nil { jws = r.jwsRepresentation }
        }
        isMember = jws != nil  // 仅用于展示；配额以服务端为准
        if let jws { await sync(jws: jws) }
    }
    /// 服务端用 App Store Server Library 校验 JWS 后写 users.isMember / memberExpiresAt
    private func sync(jws: String) async {
        do {
            let r = try await Functions.functions(region: "asia-east2").httpsCallable("syncMembership").call(["signedTransaction": jws])
            if let ok = (r.data as? [String: Any])?["isMember"] as? Bool { isMember = ok }
        } catch { lastError = "会员同步失败：\(error.localizedDescription)" }
    }
    func restore() async { try? await AppStore.sync(); await refresh() }
}

// MARK: - Chat
final class ChatService {
    static let shared = ChatService()
    func listenChats(uid: String, onChange: @escaping ([Chat]) -> Void) -> ListenerRegistration {
        db.collection("chats").whereField("participants", arrayContains: uid).order(by: "updatedAt", descending: true)
            .addSnapshotListener { s, _ in onChange(s?.documents.compactMap { try? $0.data(as: Chat.self) } ?? []) }
    }
    func listenMessages(chatId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        db.collection("chats").document(chatId).collection("messages").order(by: "createdAt").limit(toLast: 200)
            .addSnapshotListener { s, _ in onChange(s?.documents.compactMap { try? $0.data(as: ChatMessage.self) } ?? []) }
    }
    /// 文字与图片消息；服务端触发器会再次审核并更新 lastMessage（基础聊天永久免费）
    func send(chatId: String, text: String, image: UIImage?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !SensitiveWordFilter.contains(t) else { throw BottleError.sensitive }
        var url: String?
        if let image, let data = ImageCompressor.compress(image) {
            let ref = Storage.storage().reference().child("chats/\(chatId)/\(uid)_\(UUID().uuidString).jpg")
            let meta = StorageMetadata(); meta.contentType = "image/jpeg"
            _ = try await ref.putDataAsync(data, metadata: meta)
            url = try await ref.downloadURL().absoluteString
        }
        guard !t.isEmpty || url != nil else { return }
        var data: [String: Any] = ["senderId": uid, "text": t, "isAI": false, "createdAt": FieldValue.serverTimestamp()]
        if let url { data["imageURL"] = url }
        try await db.collection("chats").document(chatId).collection("messages").addDocument(data: data)
    }
    func blockInChat(chatId: String, otherId: String) async throws {
        _ = try await Functions.functions(region: "asia-east2").httpsCallable("blockUser").call(["targetUserId": otherId, "chatId": chatId])
    }
}

// MARK: - 设备标识（用于确认举报后的设备封禁）
enum DeviceIdentity {
    static var id: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    static func register() async {
        _ = try? await Functions.functions(region: "asia-east2").httpsCallable("registerDevice").call(["deviceId": id])
    }
}

private extension String {
    /// Firebase uid 不是 UUID；用 SHA256 前 16 字节派生稳定的 UUID 作为 appAccountToken
    var uuidLike: String {
        let h = Array(SHA256.hash(data: Data(utf8)))
        let u = UUID(uuid: (h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],h[9],h[10],h[11],h[12],h[13],h[14],h[15]))
        return u.uuidString
    }
}
