import SwiftUI

/// 天空随本地时间变化：黄昏 / 入夜 / 深夜 / 黎明 / 白天（白天也保持偏暗的海边色调，保证文字可读）
struct SkyPhase {
    let name: String           // 用于首页副标题
    let title: String          // 首页主标题
    let top: Color, mid: Color, bottom: Color
    let starOpacity: Double
    let moonGlow: Double
    let beam: Double           // 灯塔光强
    let fireflies: Bool

    static func at(_ date: Date = .now, calendar: Calendar = .current) -> SkyPhase {
        let h = calendar.component(.hour, from: date)
        switch h {
        case 17..<19: return SkyPhase(name: L("sky.dusk"), title: L("sky.dusk.title"), top: Color(hex: 0x2A2850), mid: Color(hex: 0x4A3A5E), bottom: Color(hex: 0xC9855A),
                                      starOpacity: 0.25, moonGlow: 0.5, beam: 0.6, fireflies: false)
        case 19..<23: return SkyPhase(name: L("sky.evening"), title: L("sky.evening.title"), top: Color(hex: 0x22305A), mid: Theme.deep, bottom: Theme.night,
                                      starOpacity: 0.85, moonGlow: 1, beam: 1, fireflies: true)
        case 23..<24, 0..<4: return SkyPhase(name: L("sky.late"), title: L("sky.late.title"), top: Color(hex: 0x161F42), mid: Color(hex: 0x0A1026), bottom: Color(hex: 0x05081A),
                                      starOpacity: 1, moonGlow: 1, beam: 1, fireflies: true)
        case 4..<7: return SkyPhase(name: L("sky.dawn"), title: L("sky.dawn.title"), top: Color(hex: 0x1C2A55), mid: Color(hex: 0x3B4A7A), bottom: Color(hex: 0xD9A27A),
                                      starOpacity: 0.35, moonGlow: 0.6, beam: 0.5, fireflies: false)
        default: return SkyPhase(name: L("sky.day"), title: L("sky.day.title"), top: Color(hex: 0x2B4A7E), mid: Color(hex: 0x3D6497), bottom: Color(hex: 0x86A9C9),
                                 starOpacity: 0, moonGlow: 0.35, beam: 0.2, fireflies: false)
        }
    }
}

/// v2 首页背景：天空（随时间）+ 星星 + 月亮 + 灯塔光束（8 秒一圈）+ 萤火虫 + 原有海浪 + 沙滩
struct NightBeachBackground: View {
    var showLighthouse = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        // 每分钟检查一次时段即可；动画层各自用 TimelineView
        TimelineView(.everyMinute) { tl in
            let phase = SkyPhase.at(tl.date)
            ZStack {
                LinearGradient(stops: [.init(color: phase.top, location: 0), .init(color: phase.mid, location: 0.45), .init(color: phase.bottom, location: 0.75)],
                               startPoint: .top, endPoint: .bottom)
                StarsAndMoon(phase: phase)
                if showLighthouse { LighthouseLayer(intensity: phase.beam) }
                AnimatedSea()
                Canvas { ctx, size in
                    let sand = SeaLayout.sandHeight(size)
                    let r = CGRect(x: 0, y: size.height - sand, width: size.width, height: sand)
                    ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(hex: 0x3A3346), Color(hex: 0x1B1828)]),
                                                           startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
                }
                if phase.fireflies { FirefliesLayer() }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct StarsAndMoon: View {
    let phase: SkyPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || phase.starOpacity == 0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                var seed: UInt64 = 7
                func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
                for i in 0..<90 {
                    let p = CGPoint(x: next() * size.width, y: next() * SeaLayout.horizonY(size)), r = 0.6 + next() * 1.1
                    let tw = 0.65 + 0.35 * sin(t * (0.8 + Double(i % 5) * 0.3) + Double(i))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r * 2, height: r * 2)), with: .color(.white.opacity(phase.starOpacity * tw)))
                }
                let m = SeaLayout.moon(size), d = SeaLayout.moonDiameter(size)
                // 光晕
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - d * 1.6, y: m.y - d * 1.6, width: d * 3.2, height: d * 3.2)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xFFE9B8).opacity(0.28 * phase.moonGlow), .clear]), center: m, startRadius: d * 0.4, endRadius: d * 1.6))
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - d / 2, y: m.y - d / 2, width: d, height: d)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6DE), Color(hex: 0xF3DDA8)]), center: CGPoint(x: m.x - d * 0.15, y: m.y - d * 0.15), startRadius: 0, endRadius: d * 0.6))
            }
        }
    }
}

/// 左侧灯塔，光束每 8 秒扫过一圈（cos 投影模拟旋转）；Reduce Motion 时为静止的柔光
struct LighthouseLayer: View {
    var intensity: Double = 1
    static let period: Double = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let u = SeaLayout.unit(size), hz = SeaLayout.horizonY(size)
                let base = CGPoint(x: size.width * 0.11, y: hz + 2)
                let towerH = 46 * u, lamp = CGPoint(x: base.x, y: base.y - towerH - 6 * u)
                // 光束
                let phase = reduceMotion ? 0.0 : (t.truncatingRemainder(dividingBy: Self.period)) / Self.period * 2 * .pi
                let facing = cos(phase)                         // 1 = 朝向屏幕右侧
                let strength = (reduceMotion ? 0.45 : max(0, facing)) * intensity
                if strength > 0.01 {
                    let len = size.width * (0.35 + 0.6 * max(0, facing)) * (reduceMotion ? 1.3 : 1)
                    let spread = 30 * u * (0.6 + 0.4 * strength)
                    var beam = Path()
                    beam.move(to: lamp)
                    beam.addLine(to: CGPoint(x: lamp.x + len, y: lamp.y - spread))
                    beam.addLine(to: CGPoint(x: lamp.x + len, y: lamp.y + spread * 0.9))
                    beam.closeSubpath()
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 6))
                        l.fill(beam, with: .linearGradient(Gradient(colors: [Theme.amber.opacity(0.55 * strength), Theme.amber.opacity(0)]),
                                                         startPoint: lamp, endPoint: CGPoint(x: lamp.x + len, y: lamp.y)))
                    }
                }
                // 背向时灯头闪一下（光束扫过观众）
                let flash = reduceMotion ? 0 : pow(max(0, -cos(phase)), 12)
                ctx.fill(Path(ellipseIn: CGRect(x: lamp.x - 22 * u, y: lamp.y - 22 * u, width: 44 * u, height: 44 * u)),
                         with: .radialGradient(Gradient(colors: [Theme.amber.opacity(0.5 + 0.5 * flash), .clear]), center: lamp, startRadius: 0, endRadius: 22 * u))
                // 塔身
                var tower = Path()
                tower.move(to: CGPoint(x: base.x - 7 * u, y: base.y))
                tower.addLine(to: CGPoint(x: base.x - 4.5 * u, y: base.y - towerH))
                tower.addLine(to: CGPoint(x: base.x + 4.5 * u, y: base.y - towerH))
                tower.addLine(to: CGPoint(x: base.x + 7 * u, y: base.y))
                tower.closeSubpath()
                ctx.fill(tower, with: .color(Color(hex: 0x1A2240)))
                for k in 1...2 { let y = base.y - towerH * CGFloat(k) / 3
                    ctx.fill(Path(CGRect(x: base.x - 6 * u, y: y, width: 12 * u, height: 3 * u)), with: .color(Color(hex: 0x6B3A3A).opacity(0.8))) }
                ctx.fill(Path(roundedRect: CGRect(x: lamp.x - 4 * u, y: lamp.y - 4 * u, width: 8 * u, height: 9 * u), cornerRadius: 2), with: .color(Color(hex: 0xFFE2A6)))
                var roof = Path(); roof.move(to: CGPoint(x: lamp.x - 6 * u, y: lamp.y - 4 * u)); roof.addLine(to: CGPoint(x: lamp.x, y: lamp.y - 10 * u))
                roof.addLine(to: CGPoint(x: lamp.x + 6 * u, y: lamp.y - 4 * u)); roof.closeSubpath()
                ctx.fill(roof, with: .color(Color(hex: 0x1A2240)))
            }
        }
    }
}

/// 沙滩与浅海上方的萤火虫：缓慢漂移 + 呼吸闪烁；Reduce Motion 时静止
struct FirefliesLayer: View {
    var count = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                var seed: UInt64 = 42
                func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
                let top = SeaLayout.horizonY(size) - size.height * 0.12, bottom = size.height - SeaLayout.sandHeight(size) * 0.3
                for _ in 0..<count {
                    let bx = next() * size.width, by = top + next() * (bottom - top)
                    let sp = 0.15 + next() * 0.25, ph = next() * 6.28
                    let x = bx + 18 * sin(t * sp + ph), y = by + 10 * sin(t * sp * 1.3 + ph * 2)
                    let glow = reduceMotion ? 0.6 : 0.25 + 0.75 * pow((sin(t * (0.6 + sp) + ph) + 1) / 2, 3)
                    let p = CGPoint(x: x, y: y)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 7, y: y - 7, width: 14, height: 14)),
                             with: .radialGradient(Gradient(colors: [Theme.firefly.opacity(0.45 * glow), .clear]), center: p, startRadius: 0, endRadius: 7))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(Theme.firefly.opacity(glow)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
