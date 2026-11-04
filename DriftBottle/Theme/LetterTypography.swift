import SwiftUI
import UIKit
import CoreText

/// 信件字体渲染。只使用 iOS 自带字体（Apple 授权，随系统提供，无需打包）：
/// - 默认：系统衬线体
/// - 楷体：Kaiti SC（iOS 系统可下载字体，首次使用时由系统按需下载；下载前回退到衬线体）
/// - 手写：Bradley Hand（拉丁字母）+ Xingkai SC 行楷（中文，系统可下载字体）
/// - 打字机：American Typewriter（中文等字符自动回退到系统字体）
enum LetterTypography {
    static let kai = "STKaitiSC-Regular"
    static let xingkai = "STXingkaiSC-Light"
    static let bradley = "BradleyHandITCTT-Bold"
    static let typewriter = "AmericanTypewriter"

    /// 基准字号（再按动态字体缩放）
    static func pointSize(_ size: LetterSize) -> CGFloat {
        switch size { case .small: 16; case .medium: 20; case .large: 25 }
    }

    /// 需要系统按需下载的字体
    static func downloadNames(_ f: LetterFont) -> [String] {
        switch f { case .kai: [kai]; case .hand: [xingkai, kai]; default: [] }
    }

    static func uiFont(_ f: LetterFont, size: LetterSize, scale: CGFloat = 1) -> UIFont {
        let pt = pointSize(size) * scale
        let serif = UIFont.systemFont(ofSize: pt).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: pt).fontDescriptor
        let available: (String) -> Bool = { UIFont(name: $0, size: pt) != nil }
        let chain: [String]
        switch f {
        case .standard: chain = []
        case .kai: chain = [kai]
        case .hand: chain = [bradley, xingkai, kai]
        case .typewriter: chain = [typewriter]
        }
        let names = chain.filter(available)
        var desc: UIFontDescriptor
        if let first = names.first {
            desc = UIFontDescriptor(name: first, size: pt)
            var cascade = names.dropFirst().map { UIFontDescriptor(name: $0, size: pt) }
            cascade.append(serif)
            desc = desc.addingAttributes([.cascadeList: cascade])
        } else {
            desc = serif
        }
        let base = UIFont(descriptor: desc, size: pt)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    static func font(_ f: LetterFont, size: LetterSize, scale: CGFloat = 1) -> Font {
        Font(uiFont(f, size: size, scale: scale) as CTFont)
    }
}

/// 按需下载系统字体（Kaiti SC / Xingkai SC）。下载完成后 revision 递增，观察它的视图会重新渲染。
final class LetterFontLoader: ObservableObject {
    static let shared = LetterFontLoader()
    @Published private(set) var revision = 0
    private var requested = Set<String>()

    func ensure(_ f: LetterFont) {
        for name in LetterTypography.downloadNames(f) where UIFont(name: name, size: 12) == nil && !requested.contains(name) {
            requested.insert(name)
            let desc = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
            _ = CTFontDescriptorMatchFontDescriptorsWithProgressHandler([desc] as CFArray, nil) { state, _ in
                if state == .didFinish {
                    DispatchQueue.main.async { LetterFontLoader.shared.revision += 1 }
                }
                return true
            }
        }
    }
}
