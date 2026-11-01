import SwiftUI

// v4 拟物动画（对应 ui-mockups/v4/anim/*.mp4 与 src/anim.html 的时间轴）
// 坐标按 390×844 设计稿换算到实际尺寸；Reduce Motion 时改为简单淡入淡出。

private func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { Ease.clamp((t - a) / (b - a)) }
private func eio(_ t: Double) -> Double { Ease.inOut(t) }
private func eo(_ t: Double) -> Double { Ease.outCubic(t) }

/// 设计稿坐标 → 屏幕坐标
private struct Stage {
    let size: CGSize
    var sx: CGFloat { size.width / 390 }
    var sy: CGFloat { size.height / 844 }
    var k: CGFloat { min(sx, sy) }
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
    var bottleW: CGFloat { 200 * k }
    var paperW: CGFloat { min(size.width * 0.78, 330 * k) }
}

/// 签名笔迹（单位坐标，trim 动画）
private struct SignatureShape: Shape {
    func path(in r: CGRect) -> Path {
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: q(0.02, 0.7))
        p.addCurve(to: q(0.16, 0.15), control1: q(0.08, 0.55), control2: q(0.1, 0.1))
        p.addCurve(to: q(0.2, 0.85), control1: q(0.22, 0.2), control2: q(0.12, 0.9))
        p.addCurve(to: q(0.38, 0.45), control1: q(0.28, 0.8), control2: q(0.3, 0.4))
        p.addCurve(to: q(0.46, 0.75), control1: q(0.46, 0.5), control2: q(0.4, 0.8))
        p.addCurve(to: q(0.62, 0.3), control1: q(0.52, 0.7), control2: q(0.56, 0.25))
        p.addCurve(to: q(0.7, 0.8), control1: q(0.68, 0.35), control2: q(0.62, 0.85))
        p.addCurve(to: q(0.98, 0.4), control1: q(0.8, 0.75), control2: q(0.9, 0.35))
        return p
    }
}

private struct Cork: View {
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 4)
            .fill(RadialGradient(colors: [Color(hex: 0xD9A874), Color(hex: 0x9A6A3A), Color(hex: 0x6B4521)], center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: 16))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 2)
    }
}

/// 卷起的信纸
private struct Scroll: View {
    var body: some View {
        Capsule().fill(LinearGradient(colors: [Color(hex: 0xF3E2B8), Color(hex: 0xC9A66B), Color(hex: 0xE8D19E)], startPoint: .top, endPoint: .bottom))
            .overlay(Rectangle().fill(Color(hex: 0x8B6A3A)).frame(width: 6))     // 麻绳
            .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
    }
}

/// 水花：三圈涟漪 + 18 颗水滴 + 水柱
private struct SplashLayer: View {
    let t0: Double, t: Double, center: CGPoint, scale: CGFloat
    var body: some View {
        Canvas { ctx, _ in
            let u = t - t0
            guard u >= 0 else { return }
            for i in 0..<3 {
                let v = seg(u - Double(i) * 0.25, 0, 1.4)
                guard v > 0 && v < 1 else { continue }
                let w = (20 + v * 140) * scale
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - w / 2, y: center.y - w * 0.16, width: w, height: w * 0.32)),
                           with: .color(.white.opacity((1 - v) * 0.9)), lineWidth: 1.5)
            }
            if u < 0.9 {
                for i in 0..<18 {
                    let a = Double(i) / 18 * .pi - .pi, sp = 40 + Double((i * 37) % 30)
                    let x = center.x + CGFloat(cos(a) * sp * u * 1.4) * scale
                    let y = center.y + CGFloat(sin(a) * sp * 1.8 * u + 260 * u * u) * scale
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 5)), with: .color(Color(hex: 0xDCF0FF).opacity(1 - u / 0.9)))
                }
            }
            if u < 0.5 {
                let hh = 60 * sin(u / 0.5 * .pi) * scale
                let r = CGRect(x: center.x - 8 * scale, y: center.y - hh, width: 16 * scale, height: hh)
                ctx.fill(Path(roundedRect: r, cornerSize: CGSize(width: 8 * scale, height: 8 * scale)),
                         with: .linearGradient(Gradient(colors: [.white.opacity(0.9), Color(hex: 0xFFD2AA).opacity(0.2)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            }
        }
        .allowsHitTesting(false)
    }
}

private extension DayPart {
    static var current: DayPart { .at() }
}

// MARK: - 扔瓶：签名 → 卷信 → 装瓶 → 压瓶塞 → 抛物线旋转 → 水花涟漪 → 漂远
struct ThrowAnimationView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    static let total = 6.4
    private let part = DayPart.current

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(start)
                if reduceMotion { reduced(Stage(size: geo.size), t) } else { scene(Stage(size: geo.size), t) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement().accessibilityLabel(L("a11y.thrown"))
        .task { await run() }
    }

    private func run() async {
        start = Date()
        if reduceMotion { Haptics.success(); try? await Task.sleep(for: .seconds(0.9)); onFinish(); return }
        func at(_ s: Double) async { let d = s - Date().timeIntervalSince(start); if d > 0 { try? await Task.sleep(for: .seconds(d)) } }
        await at(0.25); SoundFX.shared.play(.pen, volume: 0.9, for: 1.2, fade: 0.2)       // 签名
        await at(1.7); SoundFX.shared.play(.paper, volume: 0.6)                             // 卷信
        await at(2.95); Haptics.impact(.rigid); SoundFX.shared.play(.cork, volume: 0.7)     // 压瓶塞
        await at(3.35); Haptics.impact(.medium); SoundFX.shared.play(.throwWhoosh)
        await at(4.45); Haptics.impact(.heavy); SoundFX.shared.play(.splash)
        await at(4.6); Haptics.impact(.light, intensity: 0.6)
        await at(Self.total); onFinish()
    }

    @ViewBuilder private func scene(_ s: Stage, _ t: Double) -> some View {
        let pw = s.paperW, ph = pw * 1152 / 864
        let paperC = s.p(195, 400)
        let r = eio(seg(t, 1.7, 2.25))
        ZStack {
            Color.black.opacity(0.55 * seg(t, 0, 0.3) * (1 - seg(t, 2.6, 3.0) * 0.9)).ignoresSafeArea()

            // 信纸 + 签名（0.25–1.45s 笔迹描出）
            ZStack {
                Image("Parchment").resizable()
                SignatureShape().trim(from: 0, to: seg(t, 0.25, 1.45))
                    .stroke(Color(hex: 0x2A1A0C), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: pw * 0.45, height: ph * 0.08)
                    .offset(x: pw * 0.12, y: ph * 0.3)
            }
            .frame(width: pw, height: ph)
            .scaleEffect(x: 1 - r * 0.6, y: (1 - r * 0.6) * (1 - r * 0.93))
            .offset(y: -r * 40 * s.k)
            .position(paperC)
            .opacity(1 - seg(t, 2.15, 2.3))

            // 羽毛笔沿笔迹移动
            if t < 1.7 {
                let w = seg(t, 0.25, 1.45)
                let tip = signaturePoint(w, in: CGRect(x: paperC.x - pw * 0.105, y: paperC.y + ph * 0.26, width: pw * 0.45, height: ph * 0.08))
                Image(systemName: "pencil").font(.system(size: 40 * s.k, weight: .bold)).engraved(Color(hex: 0x3B2A16))
                    .rotationEffect(.degrees(-62 + sin(t * 20) * 2), anchor: .bottomLeading)
                    .position(x: tip.x + 14 * s.k, y: tip.y - 14 * s.k)
                    .opacity(t < 0.15 ? seg(t, 0, 0.15) : 1 - seg(t, 1.5, 1.7))
            }

            // 卷好的信滑入瓶中 2.25–2.7
            if t > 2.2 && t < 2.75 {
                let q = eio(seg(t, 2.25, 2.7))
                Scroll().frame(width: 120 * s.k * (1 - q * 0.55), height: 30 * s.k * (1 - q * 0.55))
                    .rotationEffect(.degrees(-38 * q))
                    .position(x: paperC.x, y: s.p(0, 440).y + q * 40 * s.k)
            }

            bottle(s, t)

            // 瓶塞落下 + 挤压 2.75–3.15
            if t > 2.7 && t < 3.25 {
                let c = seg(t, 2.75, 3.15)
                let sq = c > 0.5 ? 0.25 * sin((c - 0.5) * 2 * .pi) : 0
                let neck = CGPoint(x: s.p(195, 0).x + s.bottleW * 0.27, y: s.p(0, 430).y - s.bottleW * 0.37)
                Cork().frame(width: 22 * s.k, height: 20 * s.k)
                    .scaleEffect(x: 1 + sq, y: 1 - sq)
                    .rotationEffect(.degrees(40))
                    .position(x: neck.x, y: neck.y - 60 * s.k * (1 - eo(min(1, c * 2))))
            }

            let water = s.p(315, 560)
            SplashLayer(t0: 4.45, t: t, center: water, scale: 0.8 * s.k)
        }
    }

    @ViewBuilder private func bottle(_ s: Stage, _ t: Double) -> some View {
        let W = s.bottleW
        let img = BottleImage(screenBlend: part.screenBlendBottle).frame(width: W)
        if t < 3.35 {
            let bsy = t > 3.0 && t < 3.3 ? 1 - 0.08 * sin(seg(t, 3.0, 3.3) * .pi) : 1
            // 装信 / 压瓶塞阶段用空瓶 + 单独绘制的信卷与瓶塞；瓶塞落定（3.15s）后换成完整瓶子
            ZStack {
                if t < 3.15 {
                    EmptyBottleImage().frame(width: W)
                    if t >= 2.7 { Scroll().frame(width: 54 * s.k, height: 13.5 * s.k).rotationEffect(.degrees(-38)) }
                } else { img }
            }
            .scaleEffect(x: 1 / bsy, y: bsy, anchor: .bottom)
            .position(s.p(195, 430)).opacity(seg(t, 1.9, 2.2))
        } else if t < 4.45 {
            let q = seg(t, 3.35, 4.45)
            let x = Ease.lerp(195, 315, q), y = Ease.lerp(430, 560, q) - 420 * CGFloat(q * (1 - q)) * 1.2
            img.scaleEffect(1 - 0.88 * eo(q)).rotationEffect(.degrees(q * 900)).position(s.p(x, y))
        } else {
            let q = seg(t, 4.45, 6.2)
            let pos = s.p(315 + q * 8, 560 - q * 16 + sin(t * 5) * 1.5)
            ZStack {
                Ellipse().stroke(.white.opacity(0.4), lineWidth: 1).frame(width: 32 * s.k, height: 8 * s.k).offset(y: 10 * s.k)
                img.scaleEffect(0.12 - 0.07 * q).rotationEffect(.degrees(-15 + sin(t * 3) * 12))
            }
            .position(pos)
            .opacity(t < 4.6 ? seg(t, 4.45, 4.6) : 1 - seg(t, 5.6, 6.2) * 0.7)
            .opacity(1 - seg(t, 6.0, 6.4))
        }
    }

    private func signaturePoint(_ w: Double, in r: CGRect) -> CGPoint {
        // 用 trimmedPath 的终点近似笔尖位置
        let p = SignatureShape().path(in: r).trimmedPath(from: 0, to: max(0.001, w))
        return p.currentPoint ?? CGPoint(x: r.minX, y: r.midY)
    }

    @ViewBuilder private func reduced(_ s: Stage, _ t: Double) -> some View {
        BottleImage(screenBlend: part.screenBlendBottle).frame(width: s.bottleW * 0.6)
            .position(s.p(315, 560)).opacity(max(0, 1 - t / 0.9))
    }
}

// MARK: - 捡瓶：网兜入水 → 兜起 → 跟随网圈上升滴水 → 瓶塞弹出 → 信纸展开
struct PickAnimationView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    static let total = 4.8
    private let part = DayPart.current

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(start)
                let s = Stage(size: geo.size)
                if reduceMotion {
                    Image("Parchment").resizable().frame(width: s.paperW, height: s.paperW * 1152 / 864)
                        .position(s.p(195, 420)).opacity(min(1, t / 0.5))
                } else { scene(s, t) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement().accessibilityLabel(L("a11y.picked"))
        .task { await run() }
    }

    private func run() async {
        start = Date()
        if reduceMotion { Haptics.success(); try? await Task.sleep(for: .seconds(0.7)); onFinish(); return }
        func at(_ s: Double) async { let d = s - Date().timeIntervalSince(start); if d > 0 { try? await Task.sleep(for: .seconds(d)) } }
        await at(0.15); Haptics.impact(.light); SoundFX.shared.play(.netDip, volume: 0.5)
        await at(0.9); Haptics.impact(.medium, intensity: 0.8)
        await at(1.4); Haptics.impact(.heavy); SoundFX.shared.play(.pickUp)
        await at(2.95); Haptics.impact(.rigid); SoundFX.shared.play(.cork)
        await at(3.7); SoundFX.shared.play(.paper, volume: 0.7)
        await at(Self.total); Haptics.success(); onFinish()
    }

    /// 网杆角度与缩放（与 anim.html 相同的曲线）
    private func net(_ t: Double) -> (ang: Double, ss: Double) {
        let lift = eio(seg(t, 1.4, 2.4)), dip = eio(seg(t, 0.15, 0.95))
        let ang = t < 0.95 ? 50 - 20 * dip : (t < 1.4 ? 30 - 1.5 * sin(seg(t, 0.95, 1.4) * .pi) : 30 - 6.4 * lift)
        let ss = t < 0.95 ? 0.65 + 0.16 * dip + 0.06 * sin(dip * .pi) : (t < 1.4 ? 0.81 + 0.03 * sin(seg(t, 0.95, 1.4) * .pi) : 0.81 + 0.55 * lift)
        return (ang, ss)
    }
    /// 网圈中心（设计稿坐标）
    private func hoop(_ t: Double) -> CGPoint {
        let (ang, ss) = net(t), a = ang * .pi / 180, px = 110.0 - 400, py = 172.0 - 400
        return CGPoint(x: 430 + (px * cos(a) - py * sin(a)) * ss, y: 860 + (px * sin(a) + py * cos(a)) * ss)
    }

    @ViewBuilder private func scene(_ s: Stage, _ t: Double) -> some View {
        let W = s.bottleW, pw = s.paperW, ph = pw * 1152 / 864
        let h = hoop(t), hp = s.p(h.x, h.y)
        let neck = CGPoint(x: s.p(195, 0).x + W * 0.27, y: s.p(0, 420).y - W * 0.37)
        ZStack {
            Color.black.opacity(0.15 + seg(t, 2.9, 3.3) * 0.6).ignoresSafeArea()

            // 漂浮的瓶子 → 跟随网圈 → 到中央
            Group {
                let img = BottleImage(screenBlend: part.screenBlendBottle).frame(width: W)
                if t < 1.1 {
                    img.scaleEffect(0.22).rotationEffect(.degrees(-12 + sin(t * 3) * 8)).position(s.p(315, 568 + sin(t * 4) * 2))
                } else if t < 2.6 {
                    let q = eio(seg(t, 1.35, 2.6))
                    img.scaleEffect(0.22 + 0.68 * q).rotationEffect(.degrees(-12 + q * 12)).position(hp)
                } else {
                    // 瓶塞弹出（2.95s）后换空瓶，信卷单独绘制直到 3.3s 抽出
                    ZStack {
                        if t < 2.95 { img } else {
                            EmptyBottleImage().frame(width: W)
                            if t < 3.3 { Scroll().frame(width: 54 * s.k, height: 13.5 * s.k).rotationEffect(.degrees(-38)) }
                        }
                    }
                    .scaleEffect(0.9 + 0.1 * eo(seg(t, 2.6, 2.9))).position(s.p(195, 420)).opacity(1 - seg(t, 3.3, 3.6))
                }
            }

            // 网兜（Canvas：网杆 + 网圈 + 网格）
            Canvas { ctx, size in
                let (ang, ss) = net(t)
                let pivot = s.p(430, 860)
                let a = ang * .pi / 180
                func tr(_ x: Double, _ y: Double) -> CGPoint {
                    let dx = (x - 400) * ss, dy = (y - 400) * ss
                    return s.p(430 + dx * cos(a) - dy * sin(a), 860 + dx * sin(a) + dy * cos(a))
                }
                var pole = Path(); pole.move(to: pivot); pole.addLine(to: tr(140, 190))
                ctx.stroke(pole, with: .linearGradient(Gradient(colors: [Color(hex: 0x6B4521), Color(hex: 0xB08850)]), startPoint: pivot, endPoint: tr(140, 190)),
                           style: StrokeStyle(lineWidth: 9 * s.k * CGFloat(ss), lineCap: .round))
                let c = tr(110, 172), rx = 40 * ss * s.k, ry = 16 * ss * s.k
                var ell = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                ell = ell.applying(CGAffineTransform(rotationAngle: (25 + ang) * .pi / 180)).applying(CGAffineTransform(translationX: c.x, y: c.y))
                // 网袋
                var bag = Path()
                for i in 0...8 {
                    let f = Double(i) / 8
                    let top = CGPoint(x: c.x - rx + 2 * rx * f, y: c.y)
                    bag.move(to: top); bag.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 55 * ss * s.k), control: CGPoint(x: top.x, y: c.y + 40 * ss * s.k))
                }
                for j in 1...3 {
                    let d = Double(j) / 4 * 45 * ss * s.k, w = rx * (1 - Double(j) / 4.5)
                    bag.addEllipse(in: CGRect(x: c.x - w, y: c.y + d - 4, width: w * 2, height: 8))
                }
                ctx.stroke(bag, with: .color(Color(hex: 0xE8D3A6).opacity(0.8)), lineWidth: 1.2)
                ctx.stroke(ell, with: .color(Color(hex: 0xB08850)), lineWidth: 7 * ss * s.k)
                // 兜起时的水滴
                if t > 1.1 && t < 2.6 {
                    for i in 0..<10 {
                        let ph = (t * 1.7 + Double(i) * 0.13).truncatingRemainder(dividingBy: 1)
                        let p = CGPoint(x: hp.x - 30 * s.k + Double(i) * 7 * s.k, y: hp.y + 20 * ss * s.k + ph * 120 * s.k)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 5)), with: .color(Color(hex: 0xDCF0FF).opacity(1 - ph)))
                    }
                }
            }
            .opacity(seg(t, 0, 0.2) * (1 - seg(t, 2.6, 2.9)))

            SplashLayer(t0: 0.88, t: t, center: s.p(312, 568), scale: 0.55 * s.k)
            if t > 1.4 { SplashLayer(t0: 1.42, t: t, center: s.p(312, 568), scale: 0.45 * s.k) }

            // 瓶塞弹出（弧线 + 旋转 + 火花）2.95–3.6
            if t > 2.95 && t < 3.6 {
                let c = seg(t, 2.95, 3.6)
                Cork().frame(width: 22 * s.k, height: 20 * s.k).scaleEffect(1.1)
                    .rotationEffect(.degrees(40 + c * 540))
                    .position(x: neck.x + c * 60 * s.k, y: neck.y + (-c * 180 + c * c * 120) * s.k)
                    .opacity(1 - seg(t, 3.4, 3.6))
                if t < 3.1 {
                    let u = seg(t, 2.95, 3.1)
                    ForEach(0..<8, id: \.self) { i in
                        Image(systemName: "sparkle").font(.system(size: 9 * s.k)).foregroundStyle(Color(hex: 0xFFF6D0))
                            .position(x: neck.x + cos(Double(i)) * 30 * u * s.k, y: neck.y + sin(Double(i)) * 30 * u * s.k)
                            .opacity(1 - u)
                    }
                }
            }

            // 卷信抽出 3.3–3.7，展开 3.7–4.5
            if t > 3.3 && t < 3.75 {
                let q = eio(seg(t, 3.3, 3.7))
                Scroll().frame(width: 120 * s.k, height: 30 * s.k).scaleEffect(1 + q * 0.3).position(s.p(195, 435 - q * 80))
            }
            if t > 3.7 {
                let u = eo(seg(t, 3.7, 4.5))
                Image("Parchment").resizable().frame(width: pw, height: ph)
                    .scaleEffect(x: 0.4 + 0.6 * u, y: (0.4 + 0.6 * u) * (0.07 + 0.93 * u))
                    .position(s.p(195, 420))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 12)
            }
        }
    }
}
