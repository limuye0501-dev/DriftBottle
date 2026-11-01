import SwiftUI
import UIKit

// MARK: - 公共：触感、几何、缓动
enum Haptics {
    static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        let g = UIImpactFeedbackGenerator(style: s); g.prepare(); g.impactOccurred(intensity: intensity)
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// 与 NightBeachBackground 共用的布局（全屏坐标，忽略安全区）。
/// 全部按屏幕尺寸比例计算：375×812（13 mini）到 440×956（Pro Max）都保持相同构图。
enum SeaLayout {
    static func sandHeight(_ s: CGSize) -> CGFloat { (s.height * 0.106).rounded() }      // 852pt 高时约 90
    static func seaHeight(_ s: CGSize) -> CGFloat { (s.height * 0.258).rounded() }       // 852pt 高时约 220
    static func horizonY(_ s: CGSize) -> CGFloat { s.height - sandHeight(s) - seaHeight(s) }
    static func shoreY(_ s: CGSize) -> CGFloat { s.height - sandHeight(s) }
    static func moonDiameter(_ s: CGSize) -> CGFloat { min(s.width * 0.15, 70) }
    /// 月亮放在右侧约 30% 屏高处：避开刘海/灵动岛，也不被顶部通知条遮住
    static func moon(_ s: CGSize) -> CGPoint { CGPoint(x: s.width * 0.78, y: s.height * 0.3) }
    /// 动画元素的整体缩放（以 393pt 宽为基准，限制在 0.9–1.15）
    static func unit(_ s: CGSize) -> CGFloat { min(1.15, max(0.9, s.width / 393)) }

    /// 第 layer 层海浪在 x 处的高度（0 = 最远处）
    static func waveY(layer i: Int, x: CGFloat, t: Double, size: CGSize) -> CGFloat {
        let top = horizonY(size), depth = seaHeight(size)
        let f = Double(i) / 3
        let y0 = top + depth * CGFloat(0.04 + 0.3 * f)
        let amp = 2 + 6 * f, len = 70 + 110 * f, speed = (0.7 + 0.6 * f) * (i % 2 == 0 ? 1 : -1)
        let a = sin(Double(x) / len * 2 * .pi + t * speed)
        let b = sin(Double(x) / (len * 0.47) + t * 1.7 + Double(i))
        return y0 + CGFloat(amp * a + amp * 0.35 * b)
    }
}

enum Ease {
    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    static func outCubic(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }
    static func inOut(_ t: Double) -> Double { let t = clamp(t); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    static func outBack(_ t: Double) -> Double { let t = clamp(t), c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2) }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t)) }
}

// MARK: - 动态海面
struct AnimatedSea: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                SeaPainter.draw(&ctx, size: size, t: t)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

enum SeaPainter {
    static func seaHeightStep(_ s: CGSize) -> CGFloat { SeaLayout.seaHeight(s) / 18 }
    static let colors: [Color] = [Color(red: 0.05, green: 0.17, blue: 0.36), Color(red: 0.06, green: 0.22, blue: 0.43),
                                  Color(red: 0.08, green: 0.27, blue: 0.5), Color(red: 0.1, green: 0.32, blue: 0.56)]
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let top = SeaLayout.horizonY(size), shore = SeaLayout.shoreY(size)
        ctx.fill(Path(CGRect(x: 0, y: top, width: size.width, height: shore - top + 4)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.04, green: 0.14, blue: 0.3), Color(red: 0.1, green: 0.3, blue: 0.5)]),
                                       startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: shore)))
        // 月光倒影
        let mx = SeaLayout.moon(size).x
        for k in 0..<14 {
            let y = top + 6 + CGFloat(k) * seaHeightStep(size)
            let w = 14 + CGFloat(k) * 3 + CGFloat(sin(t * 2 + Double(k))) * 8
            let dx = CGFloat(sin(t * 1.3 + Double(k) * 0.9)) * 6
            ctx.fill(Path(roundedRect: CGRect(x: mx - w / 2 + dx, y: y, width: w, height: 2), cornerRadius: 1),
                     with: .color(.yellow.opacity(0.35 - Double(k) * 0.02)))
        }
        // 4 层波浪
        for i in 0..<4 {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: shore + 4))
            for x in stride(from: CGFloat(0), through: size.width + 4, by: 4) {
                p.addLine(to: CGPoint(x: x, y: SeaLayout.waveY(layer: i, x: x, t: t, size: size)))
            }
            p.addLine(to: CGPoint(x: size.width, y: shore + 4)); p.closeSubpath()
            ctx.fill(p, with: .color(colors[i].opacity(0.85)))
            var crest = Path()
            for x in stride(from: CGFloat(0), through: size.width + 4, by: 4) {
                let pt = CGPoint(x: x, y: SeaLayout.waveY(layer: i, x: x, t: t, size: size))
                x == 0 ? crest.move(to: pt) : crest.addLine(to: pt)
            }
            ctx.stroke(crest, with: .color(.white.opacity(0.06 + 0.04 * Double(i))), lineWidth: 1)
        }
        // 岸边白沫：一涨一退
        let surge = CGFloat((sin(t * 0.9) + 1) / 2)
        var foam = Path()
        foam.move(to: CGPoint(x: 0, y: shore + 2))
        for x in stride(from: CGFloat(0), through: size.width + 6, by: 6) {
            foam.addLine(to: CGPoint(x: x, y: shore - 4 - surge * 10 + CGFloat(sin(Double(x) / 23 + t * 2)) * 3))
        }
        foam.addLine(to: CGPoint(x: size.width, y: shore + 2)); foam.closeSubpath()
        ctx.fill(foam, with: .color(.white.opacity(0.18 + 0.12 * Double(surge))))
    }
}

// MARK: - 瓶子绘制
enum BottlePainter {
    /// 在 center 处绘制瓶子（原始高度约 84pt），angle 弧度；corkLift 为瓶塞上移距离；letter 是否显示内部信纸
    static func draw(_ ctx: inout GraphicsContext, at center: CGPoint, scale: CGFloat, angle: Double,
                     opacity: Double = 1, corkLift: CGFloat = 0, corkAngle: Double = 0, corkOpacity: Double = 1, letter: Bool = true) {
        ctx.drawLayer { l in
            l.opacity = opacity
            l.translateBy(x: center.x, y: center.y)
            l.rotate(by: .radians(angle))
            l.scaleBy(x: scale, y: scale)
            let body = Path(roundedRect: CGRect(x: -17, y: -8, width: 34, height: 50), cornerRadius: 13)
            var shoulder = Path()
            shoulder.move(to: CGPoint(x: -15, y: 0)); shoulder.addQuadCurve(to: CGPoint(x: -6, y: -20), control: CGPoint(x: -15, y: -14))
            shoulder.addLine(to: CGPoint(x: 6, y: -20)); shoulder.addQuadCurve(to: CGPoint(x: 15, y: 0), control: CGPoint(x: 15, y: -14)); shoulder.closeSubpath()
            let neck = Path(roundedRect: CGRect(x: -6, y: -32, width: 12, height: 14), cornerRadius: 2)
            let lip = Path(roundedRect: CGRect(x: -7.5, y: -34, width: 15, height: 4), cornerRadius: 2)
            let glass = GraphicsContext.Shading.linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.9, blue: 0.85).opacity(0.55), Color(red: 0.2, green: 0.55, blue: 0.6).opacity(0.45)]),
                                                                startPoint: CGPoint(x: -17, y: 0), endPoint: CGPoint(x: 17, y: 0))
            if letter {
                // 卷起的信纸 + 红绳
                l.fill(Path(roundedRect: CGRect(x: -8, y: -12, width: 16, height: 46), cornerRadius: 7), with: .color(Color(red: 0.98, green: 0.93, blue: 0.8)))
                l.stroke(Path(roundedRect: CGRect(x: -8, y: -12, width: 16, height: 46), cornerRadius: 7), with: .color(.brown.opacity(0.4)), lineWidth: 0.8)
                l.fill(Path(CGRect(x: -8, y: 9, width: 16, height: 3)), with: .color(.red.opacity(0.8)))
            }
            for p in [body, shoulder, neck] { l.fill(p, with: glass) }
            l.stroke(body, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
            l.stroke(neck, with: .color(.white.opacity(0.7)), lineWidth: 1)
            l.fill(lip, with: .color(.white.opacity(0.55)))
            // 高光
            l.fill(Path(roundedRect: CGRect(x: -12, y: -2, width: 4, height: 34), cornerRadius: 2), with: .color(.white.opacity(0.5)))
            // 瓶塞
            l.drawLayer { c in
                c.opacity = corkOpacity
                c.translateBy(x: 0, y: -38 - corkLift)
                c.rotate(by: .radians(corkAngle))
                c.fill(Path(roundedRect: CGRect(x: -5.5, y: -6, width: 11, height: 12), cornerRadius: 2), with: .color(Color(red: 0.62, green: 0.42, blue: 0.24)))
                c.stroke(Path(roundedRect: CGRect(x: -5.5, y: -6, width: 11, height: 12), cornerRadius: 2), with: .color(.black.opacity(0.25)), lineWidth: 0.8)
            }
        }
    }
}

struct Droplet { var vx: CGFloat; var vy: CGFloat; var r: CGFloat; var delay: Double }

// 扔瓶 / 捡瓶动画见 V4Animations.swift（v4 拟物版）

enum LetterPainter {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, progress u: Double, opacity: Double = 1) {
        let w: CGFloat = min(size.width * 0.78, 340), fullH: CGFloat = min(size.height * 0.4, 400)
        let h = max(18, fullH * CGFloat(u))
        let c = CGPoint(x: size.width / 2, y: size.height * 0.46 - 40 * CGFloat(u))
        let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        ctx.drawLayer { l in
            l.opacity = opacity
            l.addFilter(.shadow(color: .black.opacity(0.4), radius: 12, y: 6))
            l.fill(Path(roundedRect: rect, cornerRadius: 6), with: .linearGradient(
                Gradient(colors: [Color(red: 0.99, green: 0.95, blue: 0.84), Color(red: 0.95, green: 0.88, blue: 0.72)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        }
        ctx.drawLayer { l in
            l.opacity = opacity
            l.clip(to: Path(rect.insetBy(dx: 0, dy: 10)))
            for i in 0..<9 {   // 文字线条（示意）
                let y = c.y - fullH / 2 + fullH * 0.15 + CGFloat(i) * fullH * 0.088
                let lw = (w - 60) * (i == 8 ? 0.45 : 1)
                l.fill(Path(roundedRect: CGRect(x: rect.minX + 30, y: y, width: lw, height: 3), cornerRadius: 1.5), with: .color(.brown.opacity(0.35)))
            }
        }
        // 上下两端的卷轴
        for y in [rect.minY, rect.maxY] {
            ctx.fill(Path(roundedRect: CGRect(x: rect.minX - 6, y: y - 7, width: w + 12, height: 14), cornerRadius: 7),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.85, blue: 0.66), Color(red: 0.8, green: 0.7, blue: 0.5)]),
                                           startPoint: CGPoint(x: 0, y: y - 7), endPoint: CGPoint(x: 0, y: y + 7)))
        }
    }
}
