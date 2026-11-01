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
    /// 月亮放在右上方，低于灵动岛/刘海区域（约 17% 屏高）
    static func moon(_ s: CGSize) -> CGPoint { CGPoint(x: s.width * 0.78, y: max(s.height * 0.17, 110)) }
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

// MARK: - 扔瓶动画：抛物线飞行 + 旋转 → 水花与涟漪 → 随浪漂远
struct ThrowAnimationView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    private let drops: [Droplet] = (0..<34).map { _ in
        Droplet(vx: .random(in: -110...110), vy: .random(in: -330 ... -120), r: .random(in: 1.2...3.4), delay: .random(in: 0...0.08))
    }
    static let flight = 1.0, splashEnd = 1.9, total = 3.6

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                if reduceMotion { drawReduced(&ctx, size: size, t: t) } else { draw(&ctx, size: size, t: t) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityLabel("瓶子已扔向大海")
        .task {
            start = Date()
            if reduceMotion { Haptics.success(); try? await Task.sleep(for: .seconds(0.7)); onFinish(); return }
            Haptics.impact(.medium)
            try? await Task.sleep(for: .seconds(Self.flight))
            Haptics.impact(.heavy)                         // 入水
            try? await Task.sleep(for: .seconds(0.12)); Haptics.impact(.light, intensity: 0.6)
            try? await Task.sleep(for: .seconds(Self.total - Self.flight - 0.12))
            onFinish()
        }
    }

    func points(_ s: CGSize) -> (from: CGPoint, splash: CGPoint, far: CGPoint) {
        (CGPoint(x: s.width * 0.42, y: SeaLayout.shoreY(s) - SeaLayout.seaHeight(s) * 0.27),
         CGPoint(x: s.width * 0.6, y: SeaLayout.horizonY(s) + SeaLayout.seaHeight(s) * 0.5),
         CGPoint(x: s.width * 0.74, y: SeaLayout.horizonY(s) + 6))
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let (p0, p1, p2) = points(size)
        if t < Self.flight {
            // 抛物线 + 旋转 + 由近及远缩小
            let u = t / Self.flight
            let arc = size.height * 0.32
            let x = Ease.lerp(p0.x, p1.x, u)
            let y = Ease.lerp(p0.y, p1.y, u) - arc * CGFloat(4 * u * (1 - u))
            // 影子
            ctx.fill(Path(ellipseIn: CGRect(x: x - 14, y: Ease.lerp(p0.y + 40, p1.y + 6, u), width: 28, height: 6)), with: .color(.black.opacity(0.25 * u)))
            BottlePainter.draw(&ctx, at: CGPoint(x: x, y: y), scale: Ease.lerp(1.25, 0.62, u) * SeaLayout.unit(size), angle: -0.4 + u * 3.6 * .pi)
            return
        }
        let dt = t - Self.flight
        // 涟漪
        for k in 0..<3 {
            let lt = dt - Double(k) * 0.18
            guard lt > 0 && lt < 1.8 else { continue }
            let r = CGFloat(8 + lt * 70)
            ctx.stroke(Path(ellipseIn: CGRect(x: p1.x - r, y: p1.y - r * 0.28, width: r * 2, height: r * 0.56)),
                       with: .color(.white.opacity(0.55 * (1 - lt / 1.8))), lineWidth: 1.6)
        }
        // 瓶子随浪漂远、缩小
        let v = Ease.inOut((t - Self.flight - 0.15) / (Self.total - Self.flight - 0.3))
        let pos = Ease.lerp(p1, p2, v)
        let bob = CGFloat(sin(t * 4.2)) * 4 * CGFloat(1 - v)
        let sink = CGFloat(max(0, 1 - dt * 3)) * 10   // 入水时先下沉再浮起
        let fade = 1 - Ease.clamp((v - 0.8) / 0.2)
        BottlePainter.draw(&ctx, at: CGPoint(x: pos.x, y: pos.y + bob + sink), scale: Ease.lerp(0.62, 0.1, v) * SeaLayout.unit(size),
                           angle: 1.2 + sin(t * 3) * 0.25, opacity: fade)
        // 瓶身下半部分被水遮住
        let wl = pos.y + bob + 4 * Ease.lerp(0.62, 0.1, v) * 6
        ctx.fill(Path(CGRect(x: pos.x - 40, y: wl, width: 80, height: 30 * Ease.lerp(0.62, 0.1, v) + 4)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.27, blue: 0.5).opacity(0.8 * fade), .clear]),
                                       startPoint: CGPoint(x: 0, y: wl), endPoint: CGPoint(x: 0, y: wl + 30)))
        // 水花粒子（重力）
        for d in drops {
            let lt = dt - d.delay
            guard lt > 0 && lt < 0.95 else { continue }
            let g: CGFloat = 720
            let x = p1.x + d.vx * CGFloat(lt)
            let y = p1.y + d.vy * CGFloat(lt) + 0.5 * g * CGFloat(lt * lt)
            ctx.fill(Path(ellipseIn: CGRect(x: x - d.r, y: y - d.r, width: d.r * 2, height: d.r * 2.6)),
                     with: .color(Color(red: 0.8, green: 0.93, blue: 1).opacity(0.9 * (1 - lt / 0.95))))
        }
        // 白色水冠
        if dt < 0.45 {
            let h = CGFloat(sin(dt / 0.45 * .pi)) * 26
            var crown = Path()
            crown.move(to: CGPoint(x: p1.x - 22, y: p1.y))
            crown.addQuadCurve(to: CGPoint(x: p1.x, y: p1.y - h), control: CGPoint(x: p1.x - 14, y: p1.y - h))
            crown.addQuadCurve(to: CGPoint(x: p1.x + 22, y: p1.y), control: CGPoint(x: p1.x + 14, y: p1.y - h))
            ctx.fill(crown, with: .color(.white.opacity(0.7)))
        }
    }

    func drawReduced(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let (_, p1, _) = points(size)
        BottlePainter.draw(&ctx, at: p1, scale: 0.7, angle: 1.2, opacity: max(0, 1 - t / 0.7))
    }
}

// MARK: - 捡瓶动画：网兜下探 → 水中摇晃 → 兜起滴水的瓶子 → 瓶塞弹开 → 信纸展开
struct PickAnimationView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    private let drips: [Droplet] = (0..<22).map { i in Droplet(vx: .random(in: -14...14), vy: .random(in: 0...40), r: .random(in: 1.2...2.6), delay: Double(i) * 0.045) }
    private let pops: [Droplet] = (0..<10).map { _ in Droplet(vx: .random(in: -120...120), vy: .random(in: -220 ... -80), r: .random(in: 1...2.2), delay: 0) }
    static let swingEnd = 0.9, swayEnd = 1.9, liftEnd = 2.8, flyEnd = 3.35, popEnd = 3.7, total = 4.5

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                if reduceMotion { drawReduced(&ctx, size: size, t: t) } else { draw(&ctx, size: size, t: t) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityLabel("捡到了一个瓶子")
        .task {
            start = Date()
            if reduceMotion { Haptics.success(); try? await Task.sleep(for: .seconds(0.6)); onFinish(); return }
            Haptics.impact(.light)
            try? await Task.sleep(for: .seconds(Self.swingEnd)); Haptics.impact(.medium, intensity: 0.8)   // 入水
            try? await Task.sleep(for: .seconds(Self.swayEnd - Self.swingEnd)); Haptics.impact(.heavy)     // 兜住
            try? await Task.sleep(for: .seconds(Self.flyEnd - Self.swayEnd)); Haptics.impact(.rigid)       // 瓶塞弹开
            try? await Task.sleep(for: .seconds(Self.total - Self.flyEnd)); Haptics.success()
            onFinish()
        }
    }

    struct Rig { let pivot: CGPoint; let length: CGFloat; let downAngle: Double }
    func rig(_ s: CGSize) -> Rig {
        let pivot = CGPoint(x: s.width + 30, y: s.height * 0.16)
        let target = CGPoint(x: s.width * 0.42, y: SeaLayout.horizonY(s) + SeaLayout.seaHeight(s) * 0.55)
        let dx = target.x - pivot.x, dy = target.y - pivot.y
        return Rig(pivot: pivot, length: hypot(dx, dy), downAngle: atan2(Double(dy), Double(dx)))
    }
    /// 杆子角度：上举 → 甩下（回弹）→ 水中摇摆 → 抬起
    func poleAngle(_ r: Rig, _ t: Double) -> Double {
        let raised = r.downAngle + 0.95, lifted = r.downAngle + 0.3
        if t < Self.swingEnd { return raised + (r.downAngle - raised) * Ease.outBack(t / Self.swingEnd) }
        if t < Self.swayEnd { return r.downAngle + 0.05 * sin((t - Self.swingEnd) * 7) }
        return r.downAngle + (lifted - r.downAngle) * Ease.inOut((t - Self.swayEnd) / (Self.liftEnd - Self.swayEnd))
    }
    func netPoint(_ r: Rig, _ t: Double) -> CGPoint {
        let a = poleAngle(r, t)
        // 抬起时同时收杆，网兜留在画面内
        let len = r.length * CGFloat(1 - 0.3 * Ease.inOut((t - Self.swayEnd) / (Self.liftEnd - Self.swayEnd)))
        return CGPoint(x: r.pivot.x + len * CGFloat(cos(a)), y: r.pivot.y + len * CGFloat(sin(a)))
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let r = rig(size)
        let center = CGPoint(x: size.width / 2, y: size.height * 0.46)
        let poleFade = 1 - Ease.clamp((t - Self.liftEnd) / 0.4)
        let np = netPoint(r, min(t, Self.liftEnd))
        let water = SeaLayout.horizonY(size) + SeaLayout.seaHeight(size) * 0.535
        let sway = CGFloat(sin(t * 5)) * 6

        if poleFade > 0 {
            ctx.drawLayer { l in
                l.opacity = poleFade
                // 杆子
                var pole = Path(); pole.move(to: r.pivot); pole.addLine(to: np)
                l.stroke(pole, with: .color(Color(red: 0.55, green: 0.38, blue: 0.2)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                l.stroke(pole, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                // 网兜：网圈 + 下垂的网袋（网格）
                let depth: CGFloat = t < Self.swayEnd ? 50 : 62
                var bag = Path()
                bag.move(to: CGPoint(x: np.x - 36, y: np.y))
                bag.addQuadCurve(to: CGPoint(x: np.x + 36, y: np.y), control: CGPoint(x: np.x + sway, y: np.y + depth * 2))
                bag.closeSubpath()
                if t >= Self.swayEnd && t < Self.flyEnd {
                    BottlePainter.draw(&l, at: CGPoint(x: np.x + sway * 0.5, y: np.y + 26), scale: 0.62, angle: 1.35 + sin(t * 5) * 0.12)
                }
                l.drawLayer { m in
                    m.clip(to: bag)
                    for k in stride(from: CGFloat(-80), through: 80, by: 9) {
                        var a = Path(); a.move(to: CGPoint(x: np.x + k, y: np.y)); a.addLine(to: CGPoint(x: np.x + k + 70, y: np.y + 110))
                        var b = Path(); b.move(to: CGPoint(x: np.x + k, y: np.y)); b.addLine(to: CGPoint(x: np.x + k - 70, y: np.y + 110))
                        m.stroke(a, with: .color(.white.opacity(0.55)), lineWidth: 0.8)
                        m.stroke(b, with: .color(.white.opacity(0.55)), lineWidth: 0.8)
                    }
                }
                l.stroke(bag, with: .color(.white.opacity(0.6)), lineWidth: 1)
                l.stroke(Path(ellipseIn: CGRect(x: np.x - 37, y: np.y - 9, width: 74, height: 18)), with: .color(Color(red: 0.75, green: 0.75, blue: 0.78)), lineWidth: 3)
                // 网兜浸在水里时，只把网袋在水面以下的部分染成海水色
                if np.y + 10 > water {
                    l.drawLayer { w in
                        var region = bag
                        region.addEllipse(in: CGRect(x: np.x - 37, y: np.y - 9, width: 74, height: 18))
                        w.clip(to: region)
                        w.clip(to: Path(CGRect(x: np.x - 80, y: water, width: 160, height: 200)))
                        w.fill(Path(CGRect(x: np.x - 80, y: water, width: 160, height: 200)), with: .color(Color(red: 0.08, green: 0.27, blue: 0.5).opacity(0.75)))
                    }
                }
            }
        }
        // 入水涟漪 / 摇晃时的涟漪
        if t > Self.swingEnd - 0.05 && t < Self.liftEnd + 0.4 {
            for k in 0..<4 {
                let lt = (t - Self.swingEnd - Double(k) * 0.35).truncatingRemainder(dividingBy: 1.4)
                guard lt > 0 else { continue }
                let rr = CGFloat(20 + lt * 55)
                ctx.stroke(Path(ellipseIn: CGRect(x: np.x - rr, y: water - rr * 0.25, width: rr * 2, height: rr * 0.5)),
                           with: .color(.white.opacity(0.4 * (1 - lt / 1.4))), lineWidth: 1.3)
            }
        }
        // 抬起时滴水
        if t > Self.swayEnd && t < Self.flyEnd + 0.5 {
            for d in drips {
                let born = Self.swayEnd + 0.1 + d.delay
                let lt = t - born
                guard lt > 0 && lt < 0.7 else { continue }
                let o = netPoint(r, min(born, Self.liftEnd))
                let x = o.x + d.vx * CGFloat(lt) + sway * 0.3
                let y = o.y + 40 + d.vy * CGFloat(lt) + 0.5 * 900 * CGFloat(lt * lt)
                ctx.fill(Path(ellipseIn: CGRect(x: x - d.r, y: y - d.r, width: d.r * 2, height: d.r * 3)),
                         with: .color(Color(red: 0.8, green: 0.93, blue: 1).opacity(0.85 * (1 - lt / 0.7))))
            }
        }
        // 瓶子飞到屏幕中央、放大、立起，瓶塞弹开
        if t >= Self.liftEnd {
            let u = Ease.outCubic((t - Self.liftEnd) / (Self.flyEnd - Self.liftEnd))
            let from = CGPoint(x: np.x, y: np.y + 26)
            let pos = Ease.lerp(from, center, u)
            let popT = t - Self.flyEnd
            let corkLift: CGFloat = popT > 0 ? CGFloat(popT * 380 - 0.5 * 900 * popT * popT) : 0
            let bottleFade = 1 - Ease.clamp((t - Self.popEnd) / 0.35)
            BottlePainter.draw(&ctx, at: pos, scale: Ease.lerp(0.62, 2.3 * SeaLayout.unit(size), u), angle: Double(Ease.lerp(1.35, 0, u)),
                               opacity: bottleFade, corkLift: corkLift, corkAngle: max(0, popT) * 9, corkOpacity: 1 - Ease.clamp(popT / 0.5),
                               letter: t < Self.popEnd)
            if popT > 0 && popT < 0.5 {
                let neck = CGPoint(x: center.x, y: center.y - 38 * 2.3 * SeaLayout.unit(size))
                for d in pops {
                    let x = neck.x + d.vx * CGFloat(popT), y = neck.y + d.vy * CGFloat(popT) + 450 * CGFloat(popT * popT)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d.r * 2, height: d.r * 2)), with: .color(.white.opacity(1 - popT / 0.5)))
                }
            }
        }
        // 信纸从瓶口升起并展开
        if t > Self.popEnd - 0.1 {
            let u = Ease.outCubic((t - Self.popEnd + 0.1) / (Self.total - Self.popEnd - 0.2))
            LetterPainter.draw(&ctx, size: size, progress: u)
        }
    }

    func drawReduced(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        LetterPainter.draw(&ctx, size: size, progress: 1, opacity: Ease.clamp(t / 0.4))
    }
}

/// 信纸展开（progress 0 → 1：卷轴从中间向上下展开）
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
