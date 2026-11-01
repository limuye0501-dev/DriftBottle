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
    @AppStorage("consumptionConsent") private var consent = false

    private var headline: String {
        switch reason {
        case .firstReply: L("paywall.h.first")
        case .quotaExhausted: L("paywall.h.quota")
        case .manual: L("paywall.h.manual")
        }
    }
    private var subline: String {
        switch reason {
        case .firstReply: L("paywall.s.first")
        case .quotaExhausted: L("paywall.s.quota", AppConstants.freeDailyLimit)
        case .manual: L("paywall.s.manual")
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("OceanNight").resizable().scaledToFill().overlay(Color.black.opacity(0.35)).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer().frame(height: 40)
                    Text(L("paywall.badge")).font(Theme.body(.caption).weight(.bold)).engraved(Theme.gold)
                    Text(headline).font(Theme.title(.title)).engraved().fixedSize(horizontal: false, vertical: true)
                    Text(subline).font(Theme.body(.subheadline)).foregroundStyle(Theme.secondary)
                    comparison
                    plans
                    Button(buying ? L("paywall.processing") : ctaTitle) { buy() }
                        .buttonStyle(BrassButtonStyle()).disabled(buying || store.tier == selected)
                    Text(L("paywall.no_refund"))
                        .font(Theme.body(.caption)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Toggle(isOn: $consent) {
                        Text(L("paywall.consent")).font(Theme.body(.caption2)).foregroundStyle(Theme.tertiary)
                    }
                    .tint(Theme.gold)
                    .onChange(of: consent) { _, v in Task { await store.setConsumptionConsent(v) } }
                    transparency
                    if let e = err ?? store.lastError { Text(e).font(Theme.body(.footnote)).foregroundStyle(.red) }
                }
                .padding(.horizontal, 22).padding(.bottom, 24)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).stamped().frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.brassGradient).shadow(color: .black.opacity(0.6), radius: 4, y: 3))
            }
            .padding(16).accessibilityLabel(L("common.close"))
        }
        .foregroundStyle(Theme.paper)
        .task { trial = await store.trialEligible(selected) }
        .onChange(of: selected) { _, t in Task { trial = await store.trialEligible(t) } }
    }

    private var ctaTitle: String {
        if store.tier == selected { return L("paywall.current", selected.title) }
        let p = selected.pricePerPeriod(store.price(selected))
        return trial ? L("paywall.trial", p) : L("paywall.subscribe", selected.title, p)
    }

    /// 三档对比：免费 / 月卡 / 年卡
    private var comparison: some View {
        VStack(spacing: 0) {
            row("", [MemberTier.free.title, MemberTier.monthly.title, MemberTier.annual.title], header: true)
            Divider().overlay(Theme.glassStroke)
            row(L("paywall.row.throws"), [L("paywall.times", AppConstants.freeDailyLimit), L("paywall.times", MemberTier.monthly.dailyLimit ?? 20), L("common.unlimited")])
            row(L("paywall.row.picks"), [L("paywall.times", AppConstants.freeDailyLimit), L("paywall.times", MemberTier.monthly.dailyLimit ?? 20), L("common.unlimited")])
            row(L("paywall.row.styles"), ["—", "—", "✓"])
            row(L("paywall.row.free_stuff"), ["✓", "✓", "✓"])   // ✓/— 为文字符号，非 emoji
        }
        .font(Theme.body(.footnote))
        .padding(14).woodPanel(18, rope: true)
        .accessibilityElement(children: .contain)
    }
    private func row(_ title: String, _ cols: [String], header: Bool = false) -> some View {
        HStack {
            Text(title).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.secondary)
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                Text(c).frame(width: typeSize.isAccessibilitySize ? nil : 64).multilineTextAlignment(.center)
                    .foregroundStyle(i == 2 ? Theme.gold : Theme.engraved).fontWeight(header || i == 2 ? .semibold : .regular)
            }
        }
        .padding(.vertical, 7)
    }

    private var plans: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            planCard(.annual, badge: L("paywall.popular"), note: store.annualPerMonth().map { L("paywall.annual_note", $0) } ?? L("paywall.annual_note_short"))
            planCard(.monthly, badge: nil, note: L("paywall.monthly_note", MemberTier.monthly.dailyLimit ?? 20))
        }
    }
    private func planCard(_ t: MemberTier, badge: String?, note: String) -> some View {
        Button { Feel.select(); selected = t } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let badge { Text(badge).font(Theme.body(.caption2).weight(.bold)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.brassGradient, in: Capsule()).stamped() }
                Text(t.title).font(Theme.body(.subheadline).weight(.semibold))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(store.price(t)).font(.system(.title, design: .serif).weight(.bold))
                    Text(t == .monthly ? L("paywall.per_month_suffix") : L("paywall.per_year_suffix")).font(Theme.body(.footnote)).foregroundStyle(Theme.secondary)
                }
                Text(note).font(Theme.body(.caption2)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if store.tier == t { Text(L("paywall.current_plan")).font(Theme.body(.caption2)).foregroundStyle(Theme.gold) }
            }
            .foregroundStyle(Theme.engraved)
            .padding(14).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .woodPanel(18)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected == t ? Theme.gold : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == t ? .isSelected : [])
    }

    /// 价格、续费、取消说明（App Store 审核 3.1.2 要求）
    private var transparency: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text([L("paywall.legal.renew", selected.title, selected.pricePerPeriod(store.price(selected))) + (trial ? " " + L("paywall.legal.trial") : ""),
                  L("paywall.legal.cancel"), L("paywall.legal.refund")].joined(separator: "\n"))
            .font(Theme.body(.caption2)).foregroundStyle(Theme.tertiary)
            HStack(spacing: 14) {
                Button(L("store.restore")) { Task { await store.restore() } }
                Button(L("store.manage")) { Task { if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene { try? await AppStore.showManageSubscriptions(in: s) } } }
                Link(L("paywall.terms"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link(L("paywall.privacy"), destination: URL(string: "https://example.com/privacy")!)   // 占位：替换为你的隐私政策
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
