import Foundation

/// 拉黑与「从我的视图移除」的本机缓存。Firestore 的 users.blockedUserIds 与 users/{uid}/blocks 是跨设备的副本。
@MainActor
final class SafetyStore: ObservableObject {
    static let shared = SafetyStore()
    @Published private(set) var blocked: Set<String>
    @Published private(set) var hiddenBottles: Set<String>
    @Published private(set) var hiddenMessages: Set<String>

    private let blockedKey = "safety.blocked.v1"
    private let bottlesKey = "safety.hiddenBottles.v1"
    private let messagesKey = "safety.hiddenMessages.v1"

    private init() {
        blocked = Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? [])
        hiddenBottles = Set(UserDefaults.standard.stringArray(forKey: bottlesKey) ?? [])
        hiddenMessages = Set(UserDefaults.standard.stringArray(forKey: messagesKey) ?? [])
    }

    func blocks(_ uid: String) -> Bool { blocked.contains(uid) }
    func hidesBottle(_ id: String?) -> Bool { id.map { hiddenBottles.contains($0) } ?? false }
    func hidesMessage(_ id: String?) -> Bool { id.map { hiddenMessages.contains($0) } ?? false }

    func rememberBlock(_ uid: String) {
        guard !uid.isEmpty else { return }
        blocked.insert(uid)
        persist()
    }
    func hideBottle(_ id: String) {
        guard !id.isEmpty else { return }
        hiddenBottles.insert(id)
        persist()
    }
    func hideMessage(_ id: String) {
        guard !id.isEmpty else { return }
        hiddenMessages.insert(id)
        persist()
    }
    /// 服务端名单与本机缓存取并集，避免刚拉黑、资料还没刷新时漏掉。
    func sync(server: [String]) {
        let merged = blocked.union(server)
        guard merged != blocked else { return }
        blocked = merged
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(blocked), forKey: blockedKey)
        UserDefaults.standard.set(Array(hiddenBottles), forKey: bottlesKey)
        UserDefaults.standard.set(Array(hiddenMessages), forKey: messagesKey)
    }
}
