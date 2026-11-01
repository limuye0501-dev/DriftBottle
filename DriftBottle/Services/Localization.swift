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
