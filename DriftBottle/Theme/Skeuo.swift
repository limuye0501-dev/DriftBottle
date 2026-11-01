import SwiftUI

// MARK: - v4 拟物 3D 组件（与 ui-mockups/v4 一致）
// 纹理在 Assets.xcassets/Textures（AI 生成的占位图，见 LICENSES.md）。
// 布局只用 leading/trailing，RTL 自动镜像；字号全部 relativeTo 文字样式，跟随动态字体。

extension Theme {
    static let brassHi = Color(hex: 0xF7DC93), brassMid = Color(hex: 0xC99A3E), brassLo = Color(hex: 0x8A5F1D), brassEdge = Color(hex: 0x5A3A10)
    static let brassInk = Color(hex: 0x3A2408)
    static let engraved = Color(hex: 0xF6E3B4)
    static let gold = Color(hex: 0xFFD77A)
    static let parchInk = Color(hex: 0x3B2A16)
    static let parchFaint = Color(hex: 0x7A5A30)
    static let brassGradient = LinearGradient(stops: [.init(color: brassHi, location: 0), .init(color: brassMid, location: 0.35),
                                                      .init(color: brassLo, location: 0.7), .init(color: Color(hex: 0xD9B160), location: 1)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: 刻字（雕刻感阴影）
struct Engraved: ViewModifier {
    var color: Color = Theme.engraved
    func body(content: Content) -> some View {
        content.foregroundStyle(color)
            .shadow(color: .black.opacity(0.8), radius: 0, x: 0, y: -1)
            .shadow(color: Color(hex: 0xFFDCA0).opacity(0.25), radius: 0, x: 0, y: 1)
    }
}
/// 黄铜面上的压印字
struct Stamped: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(Theme.brassInk)
            .shadow(color: Color(hex: 0xFFF0C8).opacity(0.6), radius: 0, x: 0, y: 1)
    }
}
extension View {
    func engraved(_ c: Color = Theme.engraved) -> some View { modifier(Engraved(color: c)) }
    func stamped() -> some View { modifier(Stamped()) }
}

// MARK: 木板 + 绳边
struct WoodPanel<S: InsettableShape>: ViewModifier {
    var shape: S
    var rope = false
    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(ImagePaint(image: Image("Wood"), scale: 0.3))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [Color(hex: 0xFFDCAA).opacity(0.3), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.6), radius: 15, y: 10)
            }
            .overlay(alignment: .top) { if rope { Rope().padding(.horizontal, 24).offset(y: -5) } }
    }
}
extension View {
    func woodPanel(_ radius: CGFloat = 26, rope: Bool = false) -> some View {
        modifier(WoodPanel(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), rope: rope))
    }
}

/// 麻绳：斜向条纹
struct Rope: View {
    var body: some View {
        Canvas { ctx, size in
            let r = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            ctx.clip(to: r)
            ctx.fill(r, with: .color(Color(hex: 0xC9A46A)))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                for (dx, w, c) in [(CGFloat(4), CGFloat(2), Color(hex: 0x8B6A3A)), (6, 3, Color(hex: 0xE2C58F)), (9, 1, Color(hex: 0x6F5025))] {
                    var p = Path(); p.move(to: CGPoint(x: x + dx, y: size.height)); p.addLine(to: CGPoint(x: x + dx + size.height * 0.47, y: 0))
                    ctx.stroke(p, with: .color(c), lineWidth: w)
                }
                x += 10
            }
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 1)), with: .color(.white.opacity(0.3)))
        }
        .frame(height: 10)
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 2)
        .accessibilityHidden(true)
    }
}

// MARK: 黄铜按钮（按下时下沉、阴影收紧）
struct BrassButtonStyle: ButtonStyle {
    var radius: CGFloat = 18
    var minHeight: CGFloat = 58
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        return configuration.label
            .font(Theme.body(.headline).weight(.bold)).stamped()
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                let s = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    s.fill(Theme.brassEdge).offset(y: p ? 1 : 4)                    // 底边厚度
                    s.fill(Theme.brassGradient).brightness(p ? -0.08 : 0)
                    s.strokeBorder(LinearGradient(colors: [Color(hex: 0xFFFADC).opacity(0.8), Color(hex: 0x3C1E00).opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.6), radius: p ? 4 : 8, y: p ? 2 : 8)
            }
            .offset(y: p ? 3 : 0)
            .saturation(enabled ? 1 : 0.3).opacity(enabled ? 1 : 0.7)
            .animation(.easeOut(duration: 0.08), value: p)
            .contentShape(Rectangle())
    }
}

/// 木质次按钮
struct WoodButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.body(.headline)).engraved()
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56)
            .woodPanel(18)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// 圆形黄铜旋钮（返回 / 关闭 / 发送）
struct BrassKnob: View {
    let systemImage: String
    var size: CGFloat = 38
    var label: String
    let action: () -> Void
    var body: some View {
        Button(action: { Feel.tap(); action() }) {
            Image(systemName: systemImage).font(.system(.body, weight: .bold)).stamped()
                .flipsForRightToLeftLayoutDirection(systemImage.contains("chevron") || systemImage.contains("arrow"))
                .frame(width: size, height: size)
        }
        .buttonStyle(KnobStyle())
        .accessibilityLabel(label)
    }
    private struct KnobStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(Circle().fill(Theme.brassGradient).shadow(color: .black.opacity(0.6), radius: configuration.isPressed ? 2 : 5, y: configuration.isPressed ? 1 : 4))
                .overlay(Circle().strokeBorder(Color(hex: 0xFFFADC).opacity(0.6), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
        }
    }
}

// MARK: 羊皮纸（撕边纹理）
struct Parchment: View {
    var body: some View {
        Image("Parchment").resizable()
            .shadow(color: .black.opacity(0.7), radius: 12, y: 14)
            .accessibilityHidden(true)
    }
}
/// 九宫格羊皮纸碎片（聊天气泡）：四边保留撕边，中间拉伸
struct ParchmentScrap: View {
    var body: some View {
        // ParchmentScrap = Parchment 缩小到 288×384 的副本，撕边约 40pt
        Image("ParchmentScrap")
            .resizable(capInsets: EdgeInsets(top: 44, leading: 40, bottom: 44, trailing: 40), resizingMode: .stretch)
            .shadow(color: .black.opacity(0.55), radius: 6, y: 6)
            .accessibilityHidden(true)
    }
}
/// 横线信纸
struct RuledLines: View {
    var spacing: CGFloat
    var body: some View {
        Canvas { ctx, size in
            var y = spacing
            while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 1)), with: .color(Color(hex: 0x785028).opacity(0.18))); y += spacing }
        }
        .accessibilityHidden(true)
    }
}

// MARK: 火漆印
struct WaxSeal: View {
    var symbol = "water.waves"
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x8A1720)).frame(width: size + 10, height: size + 10)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 4)
            Circle().fill(RadialGradient(colors: [Color(hex: 0xE0505A), Color(hex: 0x9C1C26), Color(hex: 0x5E0B12)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color(hex: 0xFF9696).opacity(0.4), lineWidth: 1.5).blur(radius: 1))
            Image(systemName: symbol).font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Color(hex: 0x5C0910))
                .shadow(color: Color(hex: 0xFF8C8C).opacity(0.5), radius: 0, y: 1)
                .shadow(color: .black.opacity(0.4), radius: 0, y: -1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: 海玻璃气泡（我的消息）
struct SeaGlass: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        let s = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius, bottomTrailingRadius: 4, topTrailingRadius: radius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: s)
            .background(LinearGradient(colors: [Color(hex: 0xA0C8DC).opacity(0.35), Color(hex: 0x3C6482).opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: s)
            .overlay(s.strokeBorder(Color(hex: 0xDCF0FF).opacity(0.35)))
            .shadow(color: .black.opacity(0.5), radius: 7, y: 6)
            .environment(\.colorScheme, .dark)
    }
}
extension View { func seaGlass(_ r: CGFloat = 18) -> some View { modifier(SeaGlass(radius: r)) } }

// MARK: 刻字 SF Symbol 图标（替代 emoji）
struct EngravedIcon: View {
    let systemName: String
    var onBrass = false
    var body: some View {
        if onBrass { Image(systemName: systemName).fontWeight(.bold).stamped() }
        else { Image(systemName: systemName).fontWeight(.semibold).engraved() }
    }
}

// MARK: 金币徽章（今日剩余次数）
struct CoinBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(RadialGradient(colors: [Color(hex: 0xFFF6C8), Color(hex: 0xD9A640), Color(hex: 0x7A5212)], center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: 7))
                .frame(width: 10, height: 10)
            Text(text).font(Theme.body(.footnote).weight(.semibold)).engraved()
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .woodPanel(16)
    }
}
