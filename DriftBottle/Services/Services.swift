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
        do { try await UserService.shared.create(p, uid: uid); profile = p; state = .ready }
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
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).updateData(["blockedUserIds": FieldValue.arrayUnion([otherId])])
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

// MARK: - Sensitive words
enum SensitiveWordFilter {
    // 示例词表；生产环境应从远程配置加载并在服务端再次校验
    static let words = ["赌博", "代孕", "毒品", "裸聊", "约炮", "加微信转账", "色情"]
    static func contains(_ s: String) -> Bool { words.contains { s.contains($0) } }
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

    func throwBack(_ id: String) async throws { _ = try await fn.httpsCallable("throwBack").call(["bottleId": id]) }
    func reply(_ id: String, text: String) async throws -> String? {
        guard !SensitiveWordFilter.contains(text) else { throw BottleError.sensitive }
        let r = try await fn.httpsCallable("replyBottle").call(["bottleId": id, "text": text])
        return (r.data as? [String: Any])?["chatId"] as? String
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
    func purchase() async throws {
        guard let product else { return }
        if case .success(.verified(let t)) = try await product.purchase() { await t.finish(); await refresh() }
    }
    func refresh() async {
        var active = false
        for await r in Transaction.currentEntitlements {
            if case .verified(let t) = r, t.productID == AppConstants.annualProductId, t.revocationDate == nil { active = true }
        }
        isMember = active
        // TODO: 服务端用 App Store Server API 校验后再写 users.isMember（客户端不可直接写）
        if active { _ = try? await Functions.functions(region: "asia-east2").httpsCallable("syncMembership").call() }
    }
    func restore() async { try? await AppStore.sync(); await refresh() }
}
