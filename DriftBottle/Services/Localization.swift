import Foundation

/// 本地化：所有界面文案在 Resources/Localizable.xcstrings（源语言 zh-Hans）。
/// 键为语义 ID（如 "home.throw"），由 tools/i18n/build.py 从 tools/i18n/*.json 生成。
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
/// 带参数：%@ 字符串、%ld 整数；支持 %1$@ 位置参数
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

enum AppLocale {
    /// 上报给服务端用于推送/审核提示语言，例如 "zh-Hans"、"pt-BR"、"en"
    static var code: String { Bundle.main.preferredLocalizations.first ?? "en" }
}

/// 条款、隐私、Apple 标准 EULA 与支持邮箱。审核与设置共用同一组地址。
enum AppLinks {
    static let terms = URL(string: "https://limuye0501-dev.github.io/DriftBottle/terms.html")!
    static let rules = URL(string: "https://limuye0501-dev.github.io/DriftBottle/terms.html#rules")!
    static let privacy = URL(string: "https://limuye0501-dev.github.io/DriftBottle/privacy.html")!
    static let eula = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "mailto:limuye0501@gmail.com")!
}
