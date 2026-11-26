import Foundation
import SwiftUI
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions
import FirebaseMessaging
import UIKit
import StoreKit
import Security

let db = Firestore.firestore()

// MARK: - Session（Firebase 匿名登录，无需注册）
@MainActor
final class SessionStore: ObservableObject {
    enum State { case loading, failed, needsOnboarding, ready }
    @Published var state: State = .loading
    @Published var profile: UserProfile?
    @Published var error: String?
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        #if DEBUG
        if Demo.on { profile = Demo.profile; state = .ready; return }
        #endif
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { await self?.refresh(user: user) }
        }
    }
    var uid: String? { Demo.on ? "demo-me" : Auth.auth().currentUser?.uid }

    /// 首次启动自动匿名登录
    func signInAnonymously() async {
        state = .loading; error = nil
        do { _ = try await Auth.auth().signInAnonymously() }
        catch { self.error = L("err.connect", error.localizedDescription); state = .failed }
    }

    func refresh(user: User?) async {
        guard let user else { profile = nil; await signInAnonymously(); return }
        profile = try? await UserService.shared.fetch(uid: user.uid)
        if let p = profile, p.locale != AppLocale.code { await UserService.shared.updateLocale() }
        if let p = profile, p.termsAcceptedAt != nil { TermsAcceptance.accept(uid: user.uid) }
        state = profile == nil ? .needsOnboarding : .ready
        if profile != nil {
            SafetyStore.shared.sync(server: profile?.blockedUserIds ?? [])
            await UserService.shared.refreshBlocks()
            await DeviceIdentity.register(); await UserService.shared.syncPushToken()
            await BottleService.shared.ensureWelcome(nickname: profile?.nickname ?? "")
        }
    }

    /// 资料由服务端创建：校验 18+、按年龄换算出生年份、按设备继承新账号限制与封禁。
    /// 必须先同意条款；同意记录写在本机，并随 createProfile 一并提交。
    func completeOnboarding(gender: Gender, age: Int, nickname: String?, acceptedTerms: Bool) async {
        guard acceptedTerms, let uid else { return }
        do {
            var data: [String: Any] = ["gender": gender.rawValue, "age": age, "deviceId": DeviceIdentity.id, "locale": AppLocale.code, "acceptedTerms": true]
            if let n = nickname?.trimmingCharacters(in: .whitespaces), !n.isEmpty { data["nickname"] = n }
            let r = try await Functions.functions(region: "europe-west1").httpsCallable("createProfile").call(data)
            if let e = (r.data as? [String: Any])?["error"] as? String { error = e; return }
            profile = try await UserService.shared.fetch(uid: uid)
            guard profile != nil else { state = .needsOnboarding; return }
            TermsAcceptance.accept(uid: uid)
            if profile?.termsAcceptedAt == nil { profile?.termsAcceptedAt = Date() }
            state = .ready
            await UserService.shared.syncPushToken()
            await BottleService.shared.ensureWelcome(nickname: profile?.nickname ?? nickname ?? "")
        } catch { self.error = L("err.save", error.localizedDescription) }
    }

    /// 老用户补记一次条款同意。本机记录立即生效；服务端时间戳在规则允许时写入，失败不挡住用户。
    func recordTermsAcceptance() async {
        guard let uid else { return }
        TermsAcceptance.accept(uid: uid)
        if profile?.termsAcceptedAt == nil { profile?.termsAcceptedAt = Date() }
        try? await db.collection("users").document(uid).updateData(["termsAcceptedAt": FieldValue.serverTimestamp()])
    }

    func updateNickname(_ n: String) async {
        let t = n.trimmingCharacters(in: .whitespaces)
        guard (1...12).contains(t.count), !SensitiveWordFilter.contains(t), let uid else { error = L("err.nickname"); return }
        do { try await db.collection("users").document(uid).updateData(["nickname": t]); profile?.nickname = t }
        catch { self.error = L("err.rename", error.localizedDescription) }
    }

    /// 注销：删除服务端数据与匿名账号（设备封禁记录与设备首次使用时间保留）
    func deleteAccount() async {
        do {
            _ = try await Functions.functions(region: "europe-west1").httpsCallable("deleteAccount").call()
            if let uid { await MainActor.run { LocalSeaStore.shared.clear(uid: uid) } }
            try await Auth.auth().currentUser?.delete()
            profile = nil
        } catch { self.error = L("err.delete", error.localizedDescription) }
    }

    static func randomNickname() -> String { L("nickname.format", Int.random(in: 1000...9999)) }
}

// MARK: - Users
final class UserService {
    static let shared = UserService()
    func fetch(uid: String) async throws -> UserProfile? {
        let doc = try await db.collection("users").document(uid).getDocument()
        return doc.exists ? try doc.data(as: UserProfile.self) : nil
    }
    /// 资料文档由服务端创建，规则只允许 update；资料不存在时（尚未完成引导）跳过，完成后由 syncPushToken 补写
    func updateFCMToken(_ t: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid).updateData(["fcmToken": t])
    }
    /// 推送与系统通知按用户语言下发（服务端读取 users.locale，缺省 en）
    func updateLocale() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid).updateData(["locale": AppLocale.code])
    }
    /// 登录/完成引导后主动拉取一次 FCM token（APNs token 到达前会失败，之后由 MessagingDelegate 回调补上）
    func syncPushToken() async {
        if let t = try? await Messaging.messaging().token() { await updateFCMToken(t) }
    }
    func block(_ otherId: String, chatId: String? = nil) async throws {
        await MainActor.run { SafetyStore.shared.rememberBlock(otherId) }
        var data: [String: Any] = ["targetUserId": otherId]
        if let chatId { data["chatId"] = chatId }
        _ = try await Functions.functions(region: "europe-west1").httpsCallable("blockUser").call(data)
        if let uid = Auth.auth().currentUser?.uid {
            try? await db.collection("users").document(uid).collection("blocks").document(otherId)
                .setData(["uid": otherId, "createdAt": FieldValue.serverTimestamp()])
        }
    }
    func refreshBlocks() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap = try? await db.collection("users").document(uid).collection("blocks").getDocuments()
        let ids = snap?.documents.map(\.documentID) ?? []
        await MainActor.run { SafetyStore.shared.sync(server: ids) }
    }
    func report(authorUid: String, bottleId: String?, messageId: String? = nil, chatId: String? = nil, reason: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = ["reporterId": uid, "targetUserId": authorUid, "authorUid": authorUid,
            "bottleId": bottleId ?? "", "reason": reason, "createdAt": FieldValue.serverTimestamp()]
        if let messageId, !messageId.isEmpty { data["messageId"] = messageId }
        if let chatId, !chatId.isEmpty { data["chatId"] = chatId }
        try await db.collection("reports").addDocument(data: data)
    }
}

// MARK: - Quota（按设备计数，服务端为准；重装不会重置）
struct QuotaInfo { var throwsUsed = 0, picksUsed = 0, throwLimit = AppConstants.freeDailyLimit, pickLimit = AppConstants.freeDailyLimit; var unlimited = false }
enum QuotaService {
    static func fetch() async -> QuotaInfo {
        guard let r = try? await Functions.functions(region: "europe-west1").httpsCallable("getQuota").call(["locale": AppLocale.code]),
              let d = r.data as? [String: Any] else { return QuotaInfo() }
        return QuotaInfo(throwsUsed: d["throws"] as? Int ?? 0, picksUsed: d["picks"] as? Int ?? 0,
                         throwLimit: d["throwLimit"] as? Int ?? AppConstants.freeDailyLimit,
                         pickLimit: d["pickLimit"] as? Int ?? AppConstants.freeDailyLimit,
                         unlimited: d["unlimited"] as? Bool ?? false)
    }
}

// MARK: - 条款同意（本机；重装后若钥匙串还在则不必再问。服务端 termsAcceptedAt 为准的备份）
enum TermsAcceptance {
    private static let service = "com.limuye.driftbottle.terms"
    private static func defaultsKey(_ uid: String) -> String { "termsAccepted." + uid }

    static func isAccepted(uid: String, profile: UserProfile?) -> Bool {
        if profile?.termsAcceptedAt != nil { return true }
        if UserDefaults.standard.bool(forKey: defaultsKey(uid)) { return true }
        return keychainHas(uid)
    }

    static func accept(uid: String) {
        UserDefaults.standard.set(true, forKey: defaultsKey(uid))
        let account = defaultsKey(uid)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data("1".utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainHas(_ uid: String) -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: defaultsKey(uid), kSecReturnData as String: false]
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - Sensitive words（与 functions/src/moderation.ts 保持一致；服务端为准）
enum SensitiveWordFilter {
    /// 中日韩等无空格文本用子串；拉丁文用词边界，避免拦住 class / grape / therapist 这类正常词。
    static let words = ["色情", "裸聊", "约炮", "一夜情", "援交", "包养", "黄片", "成人视频", "看片",
                        "强奸", "轮奸", "操你妈", "傻逼", "去死", "支那", "黑鬼",
                        "裸体", "裸體", "做爱", "做愛", "约砲", "約砲", "幹你娘", "肏你", "雞掰",
                        "弄死你", "杀了你", "殺了你", "纳粹", "納粹",
                        "赌博", "博彩", "代孕", "毒品", "冰毒", "枪支", "刷单", "贷款", "加微信转账",
                        "ポルノ", "エロ動画", "エロ画像", "援助交際", "強姦", "レイプ", "セックス", "ちんこ", "ちんぽ", "まんこ", "ファック", "殺すぞ", "氏ね", "死ね", "殺してやる", "児童ポルノ",
                        "야동", "포르노", "강간", "병신", "창녀", "씨발", "시발", "느금마", "지랄", "섹스",
                        "หนังโป๊", "ควย", "เย็ด", "ไอ้เหี้ย", "สัส",
                        "شرموطة", "عاهرة", "اغتصاب", "إباحي"]
    /// 英文及少量西语。整词匹配（Unicode 字母/数字边界），不用子串。
    private static let latinTerms = ["porn", "pornography", "porno", "hentai", "nude", "nudes", "nudity",
                                     "blowjob", "handjob", "dickpic", "nsfw", "onlyfans", "dildo", "orgasm",
                                     "cumshot", "creampie", "deepthroat", "gangbang", "threesome", "milf", "incest",
                                     "fuck", "fucking", "fucked", "fucker", "whore", "slut", "bitch", "cunt",
                                     "rape", "rapist", "raping", "pedophile", "pedo", "pédophile",
                                     "retard", "retarded", "faggot", "tranny",
                                     "nigger", "nigga", "chink", "kike", "spic", "wetback", "kys", "nazi",
                                     "pornografia", "pornografía", "pornographie", "prostituta", "violacion", "violación", "maricon", "maricón",
                                     "salope", "enculé", "encule", "niquer",
                                     "fotze", "ficken", "schwanz", "nutte", "schlampe", "vergewaltigung",
                                     "caralho", "buceta", "foder", "estupro", "putaria",
                                     "puttana", "frocio", "stupro", "pompino", "vaffanculo",
                                     "блядь", "хуй", "пизда", "ебать", "ебал", "пидор", "порно",
                                     "địt", "lồn", "cặc", "đụ", "buồi",
                                     "kontol", "memek", "ngentot", "bajingan", "perkosa",
                                     "siktir", "amcık", "amcik", "orospu", "yarrak", "tecavüz", "tecavuz"]
    private static let latinPhrases = ["kill yourself", "kill urself", "kill you", "child porn", "hijo de puta", "hija de puta",
                                       "te voy a matar", "je vais te tuer", "ich töte dich", "ti uccido", "я убью"]
    private static let boundaryRegex: NSRegularExpression? = {
        func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
        let parts = latinTerms.map(esc) + latinPhrases.map { $0.split(separator: " ").map { esc(String($0)) }.joined(separator: "\\s+") }
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(parts.joined(separator: "|")))(?![\\p{L}\\p{N}])"
        return try? NSRegularExpression(pattern: pattern)
    }()
    // 与 functions/src/moderation.ts CONTACT_KW 保持一致（多语言站外联系方式，仍需同时出现“像账号的字符串”才拦截）
    private static let kw = "(?:微信|威信|薇信|徽信|v信|vx|wx|weixin|wechat|加v|\\+v|qq|扣扣|企鹅|球球|抖音号?|小红书号?|手机号?|电话|加我|联系我|私聊我|扫码|二维码"
        + "|telegram|телеграм|tg|whatsapp|whats ?app|ватсап|واتساب|wa|line(?: ?id)?|ライン|kakao(?:talk)?|카톡|카카오톡|zalo|instagram|insta|ig|ins|snapchat|snap|viber|вайбер|skype|discord|facebook|fb|messenger|tiktok|signal|wechat id|vk|вк"
        + "|add me|dm me|contact me|agrégame|agregame|me adiciona|ekle beni|hubungi|liên hệ|kết bạn|追加して|연락)"
    private static let handle = "(?:(?=[a-z0-9_-]*\\d)[a-z][a-z0-9_-]{5,19}|\\d{5,})"
    private static let patterns: [String] = [
        kw + "[\\s:：号是为=\\-~]{0,4}" + handle,          // 关键词 + 账号
        handle + "[\\s,，]{0,2}(?:是我的?)?" + kw,            // 账号 + 关键词
        "(?<!\\d)\\d{7,}(?!\\d)",                          // 7 位以上数字（手机号/QQ）
        "(https?://|www\\.|t\\.me/|[a-z0-9-]+\\.(com|cn|net|top|xyz|io|me|vn|ru|jp|kr|br|tr|id|gg)\\b)", // 链接
        "[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}" // 邮箱
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
        if words.contains(where: { !$0.isEmpty && s.contains($0) }) { return true }
        if let re = boundaryRegex {
            let range = NSRange(s.startIndex..., in: s)
            if re.firstMatch(in: s, options: [], range: range) != nil { return true }
        }
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
    case sensitive, tooLong, empty, network, server(String)
    var errorDescription: String? {
        switch self {
        case .sensitive: return L("bottle.err.sensitive")
        case .tooLong: return L("bottle.err.too_long", AppConstants.maxBottleChars)
        case .empty: return L("bottle.err.empty")
        case .network: return L("pick.network")
        case .server(let m): return m
        }
    }
}

/// localOnly = 旧服务端说海里没瓶子时，由本机灯塔信补上（已计入本机次数）
struct PickResult { let bottle: Bottle?; let seaEmpty: Bool; let message: String?; var localOnly = false }

final class BottleService {
    static let shared = BottleService()
    private let fn = Functions.functions(region: "europe-west1")

    func throwBottle(text: String, image: UIImage?, style: BottleStyle = .classic, font: LetterFont = .standard, size: LetterSize = .medium) async throws -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw BottleError.empty }
        guard t.count <= AppConstants.maxBottleChars else { throw BottleError.tooLong }
        guard !SensitiveWordFilter.contains(t) else { throw BottleError.sensitive }
        var url: String?, path: String?
        if let image, let data = ImageCompressor.compress(image), let uid = Auth.auth().currentUser?.uid {
            let p = "bottles/\(uid)/\(UUID().uuidString).jpg"; path = p
            let ref = Storage.storage().reference().child(p)
            _ = try await ref.putDataAsync(data, metadata: { let m = StorageMetadata(); m.contentType = "image/jpeg"; return m }())
            url = try await ref.downloadURL().absoluteString
        }
        let res = try await fn.httpsCallable("throwBottle").call(["locale": AppLocale.code, "text": t, "imageURL": url as Any, "imagePath": path as Any, "style": style.rawValue, "font": font.rawValue, "fontSize": size.rawValue])
        let d = res.data as? [String: Any] ?? [:]
        if let err = d["error"] as? String { throw BottleError.server(err) }
        return d["message"] as? String ?? L("bottle.sent")
    }

    func ensureWelcome(nickname: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if await MainActor.run(body: { LocalSeaStore.shared.hasWelcome(uid) }) { return }
        do {
            let r = try await fn.httpsCallable("ensureWelcome").call(["locale": AppLocale.code])
            if let d = r.data as? [String: Any], (d["ok"] as? Bool) == true { return }
        } catch { /* 云函数未部署时用本机欢迎信，保证聊天和瓶子页不是空的 */ }
        await MainActor.run { LocalSeaStore.shared.ensureWelcome(uid: uid, nickname: nickname) }
    }

    func pickBottle() async throws -> PickResult {
        let data: Any
        do { data = try await fn.httpsCallable("pickBottle").call(["locale": AppLocale.code]).data }
        catch { throw BottleError.network }
        let d = data as? [String: Any] ?? [:]
        if let err = d["error"] as? String { throw BottleError.server(err) }
        // 旧服务端在没有别人的瓶子时返回 empty / firstVisitor，并不扣次数。本机改发一封灯塔信，并在界面上扣一次。
        if (d["empty"] as? Bool) == true || (d["firstVisitor"] as? Bool) == true {
            return try await localSeedPick()
        }
        guard let id = d["bottleId"] as? String else { throw BottleError.network }
        do {
            let b = try await db.collection("bottles").document(id).getDocument(as: Bottle.self)
            if await conceal(b) { return try await localSeedPick() }
            return PickResult(bottle: b, seaEmpty: false, message: nil)
        } catch { throw BottleError.network }
    }

    /// 词表、拉黑或「不感兴趣」命中时不展示原文，并尽量让它不再回到这个人面前。
    private func conceal(_ b: Bottle) async -> Bool {
        let blocked = await MainActor.run { SafetyStore.shared.blocks(b.senderId) || SafetyStore.shared.hidesBottle(b.id) }
        guard blocked || SensitiveWordFilter.contains(b.text) else { return false }
        if let id = b.id {
            await MainActor.run { SafetyStore.shared.hideBottle(id) }
            await hideFromMe(id)
        }
        return true
    }

    /// 立刻从自己的海里拿掉：本机记录 + hiddenBy + 放回（放回会把 uid 写入 thrownBackBy，不会再投递给自己）。
    func hideFromMe(_ id: String) async {
        guard !id.hasPrefix("local"), let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("bottles").document(id).updateData(["hiddenBy": FieldValue.arrayUnion([uid])])
        try? await release(id)
    }

    func deleteOwn(_ id: String) async throws {
        if id.hasPrefix("local") {
            let uid = Auth.auth().currentUser?.uid ?? ""
            await MainActor.run { LocalSeaStore.shared.deleteBottle(uid: uid, id: id) }
            return
        }
        do { try await db.collection("bottles").document(id).delete() }
        catch {
            let r = try await fn.httpsCallable("deleteOwnBottle").call(["bottleId": id])
            if let e = (r.data as? [String: Any])?["error"] as? String { throw BottleError.server(e) }
        }
    }

    private func localSeedPick() async throws -> PickResult {
        guard let uid = Auth.auth().currentUser?.uid else { throw BottleError.network }
        let q = await QuotaService.fetch()
        let used = q.picksUsed + (await MainActor.run { LocalSeaStore.shared.pendingPicks(uid) })
        if !q.unlimited && used >= q.pickLimit { throw BottleError.server(L("pick.quota")) }
        guard let bottle = await MainActor.run(body: { LocalSeaStore.shared.makePick(uid: uid) }) else { throw BottleError.network }
        return PickResult(bottle: bottle, seaEmpty: false, message: nil, localOnly: true)
    }

    /// 放走：瓶子继续漂向下一位真人
    func release(_ id: String) async throws {
        if id.hasPrefix("local") { return }
        _ = try await fn.httpsCallable("releaseBottle").call(["locale": AppLocale.code, "bottleId": id])
    }
    /// 保留：保留后才能回复；每个瓶子最多 3 人回复
    func keep(_ id: String) async throws {
        if id.hasPrefix("local") { return }
        let r = try await fn.httpsCallable("keepBottle").call(["locale": AppLocale.code, "bottleId": id])
        if let e = (r.data as? [String: Any])?["error"] as? String { throw BottleError.server(e) }
    }
    func reply(_ id: String, text: String) async throws -> String? {
        guard !SensitiveWordFilter.contains(text) else { throw BottleError.sensitive }
        if id.hasPrefix("local"), let uid = Auth.auth().currentUser?.uid {
            return await MainActor.run { LocalSeaStore.shared.reply(uid: uid, bottleId: id, text: text) }
        }
        let r = try await fn.httpsCallable("replyBottle").call(["locale": AppLocale.code, "bottleId": id, "text": text])
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

// MARK: - StoreKit 2 会员（订阅组：月卡 / 年卡；无免费试用）
@MainActor
final class StoreService: ObservableObject {
    @Published var products: [MemberTier: Product] = [:]
    @Published var tier: MemberTier = .free          // 展示用；配额以服务端为准
    @Published var expiresAt: Date?
    @Published var lastError: String?
    var isMember: Bool { tier != .free }
    private var updates: Task<Void, Never>?
    init() {
        updates = Task { for await r in Transaction.updates { if case .verified(let t) = r { await t.finish(); await refresh() } } }
        if Demo.on { return }
        Task { await load(); await refresh() }
    }
    func load() async {
        let ids = MemberTier.allCases.compactMap(\.productId)
        let list = (try? await Product.products(for: ids)) ?? []
        for p in list { if let t = MemberTier.from(productId: p.id) { products[t] = p } }
    }
    func price(_ t: MemberTier) -> String {
        #if DEBUG
        if Demo.on { return Demo.price(t) }
        #endif
        return products[t]?.displayPrice ?? t.fallbackPrice
    }
    /// 年卡折合每月（按商品本地货币格式化）；商品未加载时为 nil
    func annualPerMonth() -> String? {
        #if DEBUG
        if Demo.on { return Demo.annualPerMonth }
        #endif
        guard let p = products[.annual] else { return nil }
        return (p.price / 12).formatted(p.priceFormatStyle)
    }
    /// 是否展示免费试用：需同时满足配置开关打开 + 商品确有介绍性优惠 + 用户有资格
    func trialEligible(_ t: MemberTier) async -> Bool {
        guard AppConstants.offerFreeTrial, let p = products[t], p.subscription?.introductoryOffer != nil else { return false }
        return await p.subscription?.isEligibleForIntroOffer ?? false
    }
    /// 是否同意在 Apple 处理退款请求时共享使用数据（服务端字段 users.consumptionConsent）
    func setConsumptionConsent(_ v: Bool) async {
        _ = try? await Functions.functions(region: "europe-west1").httpsCallable("setConsumptionConsent").call(["consent": v])
    }
    func purchase(_ t: MemberTier) async throws {
        guard let product = products[t] else { throw BottleError.server(L("store.err.load")) }
        var opts: Set<Product.PurchaseOption> = []
        if let token = UUID(uuidString: Auth.auth().currentUser?.uid.uuidLike ?? "") { opts.insert(.appAccountToken(token)) } // 绑定账号
        switch try await product.purchase(options: opts) {
        case .success(let v):
            if case .verified(let t) = v { await t.finish() }
            await sync(jws: v.jwsRepresentation)
        case .pending: lastError = L("store.pending")
        default: break
        }
    }
    /// 同一订阅组内只会有一个有效订阅；取等级最高的那一笔交给服务端校验
    func refresh() async {
        var best: (MemberTier, String)?
        for await r in Transaction.currentEntitlements {
            guard case .verified(let t) = r, t.revocationDate == nil, let tier = MemberTier.from(productId: t.productID) else { continue }
            if best == nil || tier.rank > best!.0.rank { best = (tier, r.jwsRepresentation) }
        }
        tier = best?.0 ?? .free
        if let jws = best?.1 { await sync(jws: jws) }
    }
    /// 服务端用 App Store Server Library 校验 JWS → 商品 ID 映射等级 → 写 users.memberTier / memberExpiresAt
    private func sync(jws: String) async {
        do {
            let r = try await Functions.functions(region: "europe-west1").httpsCallable("syncMembership").call(["locale": AppLocale.code, "signedTransaction": jws])
            let d = r.data as? [String: Any] ?? [:]
            if let raw = d["tier"] as? String, let t = MemberTier(rawValue: raw) { tier = t }
            if let e = d["error"] as? String { lastError = e }
        } catch { lastError = L("store.err.sync", error.localizedDescription) }
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
        if chatId.hasPrefix("local") {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            guard !SensitiveWordFilter.contains(t) else { throw BottleError.sensitive }
            await MainActor.run { LocalSeaStore.shared.send(uid: uid, chatId: chatId, text: t) }
            return
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !SensitiveWordFilter.contains(t) else { throw BottleError.sensitive }
        var url: String?, path: String?
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
        try await UserService.shared.block(otherId, chatId: chatId)
    }
    func deleteOwnMessage(chatId: String, messageId: String) async throws {
        if chatId.hasPrefix("local") {
            let uid = Auth.auth().currentUser?.uid ?? ""
            await MainActor.run { LocalSeaStore.shared.deleteMessage(uid: uid, chatId: chatId, messageId: messageId) }
            return
        }
        do {
            try await db.collection("chats").document(chatId).collection("messages").document(messageId).delete()
        } catch {
            let r = try await Functions.functions(region: "europe-west1").httpsCallable("deleteOwnMessage").call(["chatId": chatId, "messageId": messageId])
            if let e = (r.data as? [String: Any])?["error"] as? String { throw BottleError.server(e) }
        }
    }
}

// MARK: - 设备标识（用于确认举报后的设备封禁）
enum DeviceIdentity {
    static var id: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    static func register() async {
        _ = try? await Functions.functions(region: "europe-west1").httpsCallable("registerDevice").call(["deviceId": id])
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
