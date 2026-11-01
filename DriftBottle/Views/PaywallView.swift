import SwiftUI
import StoreKit

/// 分级会员付费墙：月卡 / 年卡（订阅组内二选一，可随时升降级）。
/// 只在三种情况出现：首次收到真人回信、当日额度用完、用户手动进入。价格、续费、取消方式完整透明。
struct PaywallView: View {
    var reason: PaywallReason = .manual
    @EnvironmentObject var store: StoreService
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: MemberTier = .annual
    @State private var err: String?
    @State private var buying = false
    @State private var trial = false

    private var headline: String {
        switch reason {
        case .firstReply: "有人回信了。\n别让下一封等太久"
        case .quotaExhausted: "今晚的瓶子用完了"
        case .manual: "让更多瓶子\n漂到懂你的人手里"
        }
    }
    private var subline: String {
        switch reason {
        case .firstReply: "回信和聊天永远免费。会员只是让你每天多扔、多捡几次。"
        case .quotaExhausted: "免费用户每天扔 \(AppConstants.freeDailyLimit) 次、捡 \(AppConstants.freeDailyLimit) 次，明天会自动恢复。"
        case .manual: "回信、聊天、发图、举报与拉黑永久免费。"
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack { Theme.night; LighthouseLayer(intensity: 0.8).opacity(0.8) }.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer().frame(height: 40)
                    Text("守夜人会员").font(Theme.body(.caption)).foregroundStyle(Theme.amber)
                    Text(headline).font(Theme.title(.title)).fixedSize(horizontal: false, vertical: true)
                    Text(subline).font(Theme.body(.subheadline)).foregroundStyle(Theme.secondary)
                    comparison
                    plans
                    Button(buying ? "处理中…" : ctaTitle) { buy() }
                        .buttonStyle(AmberButtonStyle()).disabled(buying || store.tier == selected)
                    transparency
                    if let e = err ?? store.lastError { Text(e).font(Theme.body(.footnote)).foregroundStyle(.red) }
                }
                .padding(.horizontal, 22).padding(.bottom, 24)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).frame(width: 32, height: 32).glass(16)
            }
            .padding(16).accessibilityLabel("关闭")
        }
        .foregroundStyle(Theme.paper)
        .task { trial = await store.trialEligible(selected) }
        .onChange(of: selected) { _, t in Task { trial = await store.trialEligible(t) } }
    }

    private var ctaTitle: String {
        if store.tier == selected { return "当前已是\(selected.title)" }
        let p = "\(store.price(selected))/\(selected.period)"
        return trial ? "免费试用，然后 \(p)" : "订阅\(selected.title) \(p)"
    }

    /// 三档对比：免费 / 月卡 / 年卡
    private var comparison: some View {
        VStack(spacing: 0) {
            row("", ["免费", "月卡", "年卡"], header: true)
            Divider().overlay(Theme.glassStroke)
            row("每日扔瓶", ["\(AppConstants.freeDailyLimit) 次", "20 次", "不限次数"])
            row("每日捡瓶", ["\(AppConstants.freeDailyLimit) 次", "20 次", "不限次数"])
            row("专属瓶子样式", ["—", "—", "✓"])
            row("回信 · 聊天 · 发图", ["✓", "✓", "✓"])
        }
        .font(Theme.body(.footnote))
        .padding(12).glass(18)
        .accessibilityElement(children: .contain)
    }
    private func row(_ title: String, _ cols: [String], header: Bool = false) -> some View {
        HStack {
            Text(title).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.secondary)
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                Text(c).frame(width: typeSize.isAccessibilitySize ? nil : 64).multilineTextAlignment(.center)
                    .foregroundStyle(i == 2 ? Theme.amber : Theme.paper).fontWeight(header || i == 2 ? .semibold : .regular)
            }
        }
        .padding(.vertical, 7)
    }

    private var plans: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            planCard(.annual, badge: "最受欢迎", note: "约 ¥7.3/月 · 不限次数 + 专属瓶子")
            planCard(.monthly, badge: nil, note: "每天各 20 次 · 随时取消")
        }
    }
    private func planCard(_ t: MemberTier, badge: String?, note: String) -> some View {
        Button { Feel.select(); selected = t } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let badge { Text(badge).font(Theme.body(.caption2).weight(.bold)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.amber, in: Capsule()).foregroundStyle(Theme.ink) }
                Text(t.title).font(Theme.body(.subheadline).weight(.semibold))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(store.price(t)).font(.system(.title, design: .serif).weight(.bold))
                    Text("/\(t.period)").font(Theme.body(.footnote)).foregroundStyle(Theme.secondary)
                }
                Text(note).font(Theme.body(.caption2)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if store.tier == t { Text("当前方案").font(Theme.body(.caption2)).foregroundStyle(Theme.amber) }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .glass(18)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected == t ? Theme.amber : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == t ? .isSelected : [])
    }

    /// 价格、续费、取消说明（App Store 审核 3.1.2 要求）
    private var transparency: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
            \(selected.title) \(store.price(selected))/\(selected.period)，自动续期。确认购买后从 Apple ID 账户扣款；当期结束前 24 小时内自动续订并按相同价格扣费，除非你在到期前至少 24 小时关闭自动续期。\(trial ? "试用结束前未取消将开始扣费。" : "")
            如何取消：iPhone「设置」→ 你的 Apple ID →「订阅」→「漂流瓶」→「取消订阅」，或点下方「管理订阅」。取消后权益保留到当期结束。月卡与年卡可随时互相切换。
            """)
            .font(Theme.body(.caption2)).foregroundStyle(Theme.tertiary)
            HStack(spacing: 14) {
                Button("恢复购买") { Task { await store.restore() } }
                Button("管理订阅") { Task { if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene { try? await AppStore.showManageSubscriptions(in: s) } } }
                Link("条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("隐私", destination: URL(string: "https://example.com/privacy")!)   // 占位：替换为你的隐私政策
            }
            .font(Theme.body(.caption)).foregroundStyle(Theme.secondary)
        }
    }

    private func buy() {
        Feel.tap()
        Task { buying = true; defer { buying = false }
            do { try await store.purchase(selected); if store.tier == selected { Feel.success(); dismiss() } }
            catch { err = error.localizedDescription; Feel.warning() } }
    }
}
