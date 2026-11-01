import AVFoundation
import UIKit

/// 音效钩子：资源为占位文件名，需放入 Resources/Sounds/（见 README「需要的音效」）。
/// 缺文件时静默跳过；跟随系统静音键（.ambient），不打断用户正在播放的音乐。
@MainActor
final class SoundFX: ObservableObject {
    enum Effect: String, CaseIterable {
        case waves = "sfx_waves_loop"          // 海浪环境音（循环）
        case throwWhoosh = "sfx_throw_whoosh"  // 瓶子出手
        case splash = "sfx_splash"             // 入水
        case netDip = "sfx_net_dip"            // 网兜入水
        case pickUp = "sfx_pick_up"            // 捞起
        case cork = "sfx_cork_pop"             // 拔瓶塞 / 展开信纸
        case paper = "sfx_paper_unfold"        // 信纸展开
        case send = "sfx_send"                 // 发送消息/回信
        case receive = "sfx_receive"           // 收到消息
        case chime = "sfx_lighthouse_chime"    // 首次收到回信 / 灯塔
    }
    static let shared = SoundFX()
    @Published var enabled = UserDefaults.standard.object(forKey: "sfxEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "sfxEnabled"); if !enabled { stopAmbient() } }
    }
    private var players: [Effect: AVAudioPlayer] = [:]
    private init() { try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers]) }

    private func player(_ e: Effect) -> AVAudioPlayer? {
        if let p = players[e] { return p }
        guard let url = Bundle.main.url(forResource: e.rawValue, withExtension: "m4a")
                ?? Bundle.main.url(forResource: e.rawValue, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay(); players[e] = p; return p
    }
    func play(_ e: Effect, volume: Float = 1) {
        guard enabled, let p = player(e) else { return }
        p.volume = volume; p.currentTime = 0; p.play()
    }
    func startAmbient() {
        guard enabled, let p = player(.waves), !p.isPlaying else { return }
        p.numberOfLoops = -1; p.volume = 0; p.play(); p.setVolume(0.35, fadeDuration: 2)
    }
    func stopAmbient() { players[.waves]?.setVolume(0, fadeDuration: 1); Task { try? await Task.sleep(for: .seconds(1)); players[.waves]?.stop() } }
}

/// 语义化触感：所有交互统一走这里（底层仍是 Haptics）
@MainActor
enum Feel {
    static func tap() { Haptics.impact(.light, intensity: 0.7) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func sent() { Haptics.impact(.medium); SoundFX.shared.play(.send, volume: 0.6) }
    static func received() { Haptics.impact(.soft); SoundFX.shared.play(.receive, volume: 0.5) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func success() { Haptics.success() }
}
