import SwiftUI

// MARK: - v2 设计令牌（与 ui-mockups/v2 一致）
enum Theme {
    // 色板
    static let night = Color(hex: 0x070B1A)      // 最深的夜
    static let deep = Color(hex: 0x0E1630)       // 深海蓝
    static let sky = Color(hex: 0x22305A)        // 月光附近的天空
    static let paper = Color(hex: 0xF3E9D2)      // 正文 / 信纸色
    static let amber = Color(hex: 0xF5B85A)      // 强调：灯塔、主按钮
    static let amberDeep = Color(hex: 0xE89A3C)
    static let ink = Color(hex: 0x3A2E22)        // 信纸上的墨色
    static let firefly = Color(hex: 0xD8F58A)
    static let secondary = paper.opacity(0.6)
    static let tertiary = paper.opacity(0.4)
    static let glassStroke = Color.white.opacity(0.10)

    static let amberGradient = LinearGradient(colors: [Color(hex: 0xF8CB7A), amber, amberDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    // 字体：正文 PingFang SC（跟随动态字体），信件用衬线
    static func body(_ style: Font.TextStyle = .body, size: CGFloat? = nil) -> Font {
        .custom("PingFang SC", size: size ?? style.defaultSize, relativeTo: style)
    }
    static func letter(_ style: Font.TextStyle = .body) -> Font { .system(style, design: .serif) }
    static func title(_ style: Font.TextStyle = .largeTitle) -> Font { .system(style, design: .serif).weight(.semibold) }

    static let corner: CGFloat = 22
}

extension Font.TextStyle {
    /// iOS 默认（Large）字号，作为 PingFang 自定义字体的基准，再由 relativeTo 跟随动态字体
    var defaultSize: CGFloat {
        switch self {
        case .largeTitle: 34; case .title: 28; case .title2: 22; case .title3: 20
        case .headline, .body: 17; case .callout: 16; case .subheadline: 15
        case .footnote: 13; case .caption: 12; case .caption2: 11
        @unknown default: 17
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// 系统材质 + 细描边的“玻璃”卡片
struct Glass: ViewModifier {
    var radius: CGFloat = Theme.corner
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.glassStroke))
            .environment(\.colorScheme, .dark)
    }
}
extension View { func glass(_ r: CGFloat = Theme.corner) -> some View { modifier(Glass(radius: r)) } }

/// 琥珀色主按钮
struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.body(.headline).weight(.semibold)).foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(Theme.amberGradient, in: Capsule())
            .shadow(color: Theme.amber.opacity(0.35), radius: 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1).animation(.snappy, value: configuration.isPressed)
    }
}
/// 玻璃次按钮
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.body(.headline)).foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity).padding(.vertical, 15).glass(30)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

