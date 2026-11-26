import Foundation

/// 服务端仍返回「海里没有瓶子」时（云函数尚未更新），本机给出可阅读的漂流信、欢迎信和灯塔回信。
/// 网络失败不会走到这里。数据与 functions/src/seeds.data.ts 同源。
enum SeedLibrary {
    struct File: Decodable {
        var keeperGender: String
        var keeperAge: Int
        var keeperName: [String: String]
        var welcomeBottle: [String: String]
        var welcomeChat: [String: String]
        var replies: [String: [String]]
        var bottles: [String: [String]]
    }
    static let locales = ["en", "zh-Hans", "ja", "ko", "es"]
    static let data: File? = {
        guard let url = Bundle.main.url(forResource: "Seeds", withExtension: "json"),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: raw)
    }()

    static func language(_ code: String = AppLocale.code) -> String {
        if locales.contains(code) { return code }
        if code == "zh" || code.hasPrefix("zh-Hans") { return "zh-Hans" }
        return "en"
    }
    static func keeperName(_ code: String = AppLocale.code) -> String { data?.keeperName[language(code)] ?? "Lighthouse Keeper" }
    static func bottles(_ code: String = AppLocale.code) -> [String] { data?.bottles[language(code)] ?? [] }
    static func welcomeBottle(_ code: String = AppLocale.code) -> String { data?.welcomeBottle[language(code)] ?? "" }
    static func welcomeChat(_ code: String = AppLocale.code) -> String { data?.welcomeChat[language(code)] ?? "" }
    static func reply(_ code: String = AppLocale.code, salt: Int) -> String {
        let list = data?.replies[language(code)] ?? []
        guard !list.isEmpty else { return "" }
        return list[abs(salt) % list.count]
    }
    static var keeperAge: Int { data?.keeperAge ?? 36 }
    static var keeperGender: Gender { (data?.keeperGender == "male") ? .male : .female }

    static func bottle(id: String, text: String, daysAgo: Int, status: BottleStatus = .viewed) -> Bottle {
        let year = Calendar.current.component(.year, from: .now) - keeperAge
        return Bottle(id: id, senderId: "lighthouse-keeper", senderNickname: keeperName(), senderGender: keeperGender,
                      senderBirthYear: year, text: text, style: ["classic", "moonlight", "amber", "sakura"][abs(daysAgo) % 4],
                      font: "standard", fontSize: "medium", status: status,
                      createdAt: Date().addingTimeInterval(TimeInterval(-daysAgo * 86400)))
    }
}

/// 本机海：已捡过的灯塔信、欢迎信、欢迎对话，以及回信后的聊天。按 uid 存在 UserDefaults。
@MainActor
final class LocalSeaStore: ObservableObject {
    static let shared = LocalSeaStore()
    @Published private(set) var revision = 0
    private let keeper = "lighthouse-keeper"

    struct Msg: Codable { var id: String; var senderId: String; var text: String; var origin: Bool; var createdAt: Date }
    struct Thread: Codable { var id: String; var bottleId: String; var title: String; var last: String; var messages: [Msg]; var updated: Date }
    struct State: Codable { var picked: [String]; var pendingPicks: Int; var welcome: Bool; var threads: [Thread] }

    func pendingPicks(_ uid: String) -> Int { load(uid).pendingPicks }
    func hasWelcome(_ uid: String) -> Bool { load(uid).welcome }

    func ensureWelcome(uid: String, nickname: String) {
        var s = load(uid)
        guard !s.welcome, !SeedLibrary.welcomeBottle().isEmpty else { return }
        let now = Date()
        let bottleId = "local-welcome-\(uid)"
        let hello = SeedLibrary.welcomeChat()
        let origin = SeedLibrary.welcomeBottle()
        s.welcome = true
        s.threads.insert(Thread(id: "local-chat-welcome-\(uid)", bottleId: bottleId, title: SeedLibrary.keeperName(), last: hello, messages: [
            Msg(id: "o", senderId: keeper, text: origin, origin: true, createdAt: now),
            Msg(id: "h", senderId: keeper, text: hello, origin: false, createdAt: now.addingTimeInterval(1)),
        ], updated: now), at: 0)
        save(uid, s)
    }

    func welcomeBottle(uid: String) -> Bottle? {
        guard hasWelcome(uid) else { return nil }
        return SeedLibrary.bottle(id: "local-welcome-\(uid)", text: SeedLibrary.welcomeBottle(), daysAgo: 0, status: .replied)
    }

    /// 选下一封还没捡过的信，并记一次捡瓶。
    func makePick(uid: String) -> Bottle? {
        let pool = SeedLibrary.bottles()
        guard !pool.isEmpty else { return nil }
        var s = load(uid)
        let lang = SeedLibrary.language()
        var index = 0
        var reset = false
        if let next = (0..<pool.count).first(where: { !s.picked.contains("\(lang):\($0)") }) {
            index = next
        } else { index = 0; reset = true }
        let id = "local|\(lang)|\(index)"
        if reset { s.picked = ["\(lang):\(index)"] } else { s.picked.append("\(lang):\(index)") }
        s.pendingPicks += 1
        save(uid, s)
        return SeedLibrary.bottle(id: id, text: pool[index], daysAgo: index % 5)
    }

    func isLocal(_ id: String?) -> Bool { id?.hasPrefix("local") == true }

    func reply(uid: String, bottleId: String, text: String) -> String {
        var s = load(uid)
        let chatId = "local-chat-\(bottleId)"
        let now = Date()
        let scalar = Int(text.unicodeScalars.first?.value ?? 0)
        let answer = SeedLibrary.reply(salt: text.count + scalar)
        let bottleText = s.threads.first { $0.bottleId == bottleId }?.messages.first { $0.origin }?.text
            ?? SeedLibrary.bottles().first { _ in bottleId.contains(SeedLibrary.language()) } ?? ""
        let originText = textFor(bottleId) ?? bottleText
        let thread = Thread(id: chatId, bottleId: bottleId, title: SeedLibrary.keeperName(), last: answer, messages: [
            Msg(id: "o", senderId: keeper, text: originText, origin: true, createdAt: now),
            Msg(id: "u", senderId: uid, text: text, origin: false, createdAt: now.addingTimeInterval(1)),
            Msg(id: "k", senderId: keeper, text: answer, origin: false, createdAt: now.addingTimeInterval(2)),
        ], updated: now)
        s.threads.removeAll { $0.id == chatId }
        s.threads.insert(thread, at: 0)
        save(uid, s)
        return chatId
    }

    func send(uid: String, chatId: String, text: String) {
        var s = load(uid)
        guard let i = s.threads.firstIndex(where: { $0.id == chatId }) else { return }
        let now = Date()
        let answer = SeedLibrary.reply(salt: text.count + Int(now.timeIntervalSince1970) % 97)
        s.threads[i].messages.append(Msg(id: UUID().uuidString, senderId: uid, text: text, origin: false, createdAt: now))
        s.threads[i].messages.append(Msg(id: UUID().uuidString, senderId: keeper, text: answer, origin: false, createdAt: now.addingTimeInterval(1)))
        s.threads[i].last = answer
        s.threads[i].updated = now
        save(uid, s)
    }

    func chats(uid: String, nickname: String) -> [Chat] {
        load(uid).threads.map { t in
            Chat(id: t.id, participants: [uid, keeper], bottleId: t.bottleId, isAI: false, lastMessage: t.last,
                 names: [keeper: t.title, uid: nickname], updatedAt: t.updated)
        }
    }

    func messages(uid: String, chatId: String) -> [ChatMessage] {
        load(uid).threads.first { $0.id == chatId }?.messages.map { m in
            ChatMessage(id: m.id, senderId: m.senderId, text: m.text, kind: m.origin ? "origin" : nil, createdAt: m.createdAt)
        } ?? []
    }

    func deleteBottle(uid: String, id: String) {
        var s = load(uid)
        if id.contains("welcome") { s.welcome = false }
        s.threads.removeAll { $0.bottleId == id }
        save(uid, s)
    }

    func deleteMessage(uid: String, chatId: String, messageId: String) {
        var s = load(uid)
        guard let i = s.threads.firstIndex(where: { $0.id == chatId }) else { return }
        s.threads[i].messages.removeAll { $0.id == messageId }
        s.threads[i].last = s.threads[i].messages.last(where: { !$0.origin })?.text ?? s.threads[i].messages.last?.text ?? ""
        save(uid, s)
    }

    func clear(uid: String) {
        UserDefaults.standard.removeObject(forKey: key(uid))
        revision += 1
    }

    private func textFor(_ bottleId: String) -> String? {
        let parts = bottleId.split(separator: "|")
        guard parts.count == 3, let index = Int(parts[2]) else { return nil }
        let pool = SeedLibrary.data?.bottles[String(parts[1])] ?? []
        guard pool.indices.contains(index) else { return nil }
        return pool[index]
    }

    private func key(_ uid: String) -> String { "localSea.v1." + uid }
    private func load(_ uid: String) -> State {
        guard let data = UserDefaults.standard.data(forKey: key(uid)),
              let s = try? JSONDecoder().decode(State.self, from: data) else { return State(picked: [], pendingPicks: 0, welcome: false, threads: []) }
        return s
    }
    private func save(_ uid: String, _ state: State) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key(uid)) }
        revision += 1
    }
}
