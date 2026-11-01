import SwiftUI

/// v4 时段：本地时间 5/7/17/19 点切换（黎明 / 白天 / 黄昏 / 夜晚）
enum DayPart: String, CaseIterable {
    case dawn, day, dusk, night
    static func at(_ date: Date = .now, calendar: Calendar = .current) -> DayPart {
        switch calendar.component(.hour, from: date) {
        case 5..<7: .dawn
        case 7..<17: .day
        case 17..<19: .dusk
        default: .night
        }
    }
    var imageName: String { "Boardwalk" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// 夜晚用“滤色”玻璃瓶（黑底 JPG），其余时段用抠图 PNG
    var screenBlendBottle: Bool { self == .night }
    var subtitleColor: Color {
        switch self { case .night: Color(hex: 0xE6E1D2).opacity(0.8); case .dawn: Color(hex: 0x5A3448); case .day: Color(hex: 0x0D3B5A); case .dusk: Color(hex: 0xFFF1DC) }
    }
    var overlay: LinearGradient {
        let (top, bottom): (Color, Color) = switch self {
        case .night: (.black.opacity(0.35), .black.opacity(0.55))
        case .dawn: (Color(hex: 0x3C1432).opacity(0.25), Color(hex: 0x1E0F14).opacity(0.5))
        case .day: (Color(hex: 0x002850).opacity(0.25), Color(hex: 0x140F05).opacity(0.45))
        case .dusk: (Color(hex: 0x28001E).opacity(0.35), Color(hex: 0x140500).opacity(0.55))
        }
        return LinearGradient(stops: [.init(color: top, location: 0), .init(color: .clear, location: 0.18), .init(color: .clear, location: 0.62), .init(color: bottom, location: 1)], startPoint: .top, endPoint: .bottom)
    }
}

/// 栈桥背景：随时段 2.5 秒交叉淡入（Reduce Motion 时直接切换）
struct BoardwalkBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var part = DayPart.at()
    var body: some View {
        ZStack {
            ForEach(DayPart.allCases, id: \.self) { p in
                if p == part {
                    Image(p.imageName).resizable().scaledToFill()
                        .overlay(p.overlay)
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 2.5), value: part)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                let now = DayPart.at(); if now != part { part = now }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in part = DayPart.at() }
    }
}

/// 栈桥旁漂浮的玻璃瓶（上下起伏 + 轻微摇摆）；Reduce Motion 时静止
struct FloatingBottle: View {
    var part: DayPart
    var width: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            ZStack {
                Ellipse().fill(RadialGradient(colors: [Color(hex: 0xDCE6FF).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: width * 0.5))
                    .frame(width: width * 1.1, height: width * 0.18).offset(y: width * 0.42).scaleEffect(x: 1 + 0.08 * sin(t * 2))
                BottleImage(screenBlend: part.screenBlendBottle).frame(width: width)
                    .rotationEffect(.degrees(-10 + 6 * sin(t * 1.3)))
                    .offset(y: CGFloat(3 * sin(t * 1.8)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// 空玻璃瓶（无信、无瓶塞）：仅用于动画中单独绘制信卷 / 瓶塞的帧
struct EmptyBottleImage: View {
    var body: some View { Image("BottleEmpty").resizable().scaledToFit().shadow(color: .black.opacity(0.3), radius: 6, y: 6) }
}

/// 玻璃瓶图片：夜里用 JPG + 滤色混合，白天用透明 PNG + 投影
struct BottleImage: View {
    var screenBlend: Bool
    var body: some View {
        if screenBlend { Image("BottleGlass").resizable().scaledToFit().blendMode(.screen) }
        else { Image("BottleCut").resizable().scaledToFit().shadow(color: .black.opacity(0.35), radius: 6, y: 6) }
    }
}
