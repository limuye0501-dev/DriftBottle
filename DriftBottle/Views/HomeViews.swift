import SwiftUI
import PhotosUI
import FirebaseFirestore
import StoreKit

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label(L("tab.sea"), systemImage: "water.waves") }.woodTabBar()
            ChatListView().tabItem { Label(L("chat.title"), systemImage: "envelope") }.woodTabBar()
            MyBottlesView().tabItem { Label(L("tab.bottles"), systemImage: "waterbottle") }.woodTabBar()
            SettingsView().tabItem { Label(L("tab.me"), systemImage: "person") }.woodTabBar()
        }
        .tint(Theme.gold)
    }
}

private extension View {
    /// v4：木纹标签栏 + 金色选中态
    func woodTabBar() -> some View {
        toolbarBackground(ImagePaint(image: Image("Wood"), scale: 0.3), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
    }
}

/// 付费墙触发原因：只在这三种情况下出现，不在扔/捡流程中主动打扰
enum PaywallReason: String, Identifiable {
    case firstReply, quotaExhausted, manual
    var id: String { rawValue }
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var quota = QuotaInfo()
    @Published var notices: [InAppNotice] = []
    @Published var toast: String?
    @Published var picked: Bottle?
    @Published var animatingPick: Bottle?     // 先播放网兜动画，再展示信件
    @Published var throwingMessage: String?   // 非 nil 时播放扔瓶动画
    @Published var showAIFirst = false
    @Published var busy = false
    @Published var paywall: PaywallReason?
    /// 首次收到真人回信时展示一次会员页（之后只在额度用完或手动进入时出现）
    @AppStorage("didShowFirstReplyPaywall") private var didShowFirstReplyPaywall = false
    private var l: ListenerRegistration?
    private var seenNoticeIds = Set<String>()

    var throwsLeft: Int? { quota.unlimited ? nil : max(0, quota.throwLimit - quota.throwsUsed) }
    var picksLeft: Int? { quota.unlimited ? nil : max(0, quota.pickLimit - quota.picksUsed) }

    func start(uid: String, isMember: @escaping @MainActor () -> Bool) {
        Task { await reloadQuota() }
        guard l == nil else { return }
        l = BottleService.shared.listenNotices(uid: uid) { [weak self] list in Task { @MainActor in
            guard let self else { return }
            let fresh = list.filter { !self.seenNoticeIds.contains($0.id ?? "") }
            if !self.seenNoticeIds.isEmpty, !fresh.isEmpty { Feel.received() }
            fresh.forEach { self.seenNoticeIds.insert($0.id ?? "") }
            self.notices = list.sorted { $0.createdAt > $1.createdAt }
            if !self.didShowFirstReplyPaywall, !isMember(), list.contains(where: { $0.event == "replied" }) {
                self.didShowFirstReplyPaywall = true
                SoundFX.shared.play(.chime)
                Task { try? await Task.sleep(for: .seconds(1.2)); self.paywall = .firstReply }
            }
        } }
    }
    func reloadQuota() async { quota = await QuotaService.fetch() }
    func pick() async {
        busy = true; defer { busy = false }
        do {
            let r = try await BottleService.shared.pickBottle()
            await reloadQuota()
            if r.isAIFirstVisitor { showAIFirst = true } else if let b = r.bottle { animatingPick = b } else { toast = r.message }
        } catch { toast = error.localizedDescription }
    }
}

struct HomeView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var store: StoreService
    @StateObject private var m = HomeModel()
    @State private var composing = false
    @AppStorage("didShowFirstLaunchHook") private var didShowHook = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack {
            BoardwalkBackground()
            GeometryReader { geo in
                TimelineView(.everyMinute) { tl in
                    FloatingBottle(part: DayPart.at(tl.date), width: min(64, geo.size.width * 0.14))
                        .position(x: geo.size.width * (layoutDirection == .rightToLeft ? 0.2 : 0.8), y: geo.size.height * 0.62)
                }
            }
            .opacity(m.throwingMessage == nil && m.animatingPick == nil ? 1 : 0)
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(m.notices.prefix(typeSize.isAccessibilitySize ? 1 : 2)) { noticeCard($0) }
                    Spacer(minLength: 8)
                    actionButtons(width: geo.size.width)
                    if store.tier != .annual {
                        Button { Feel.tap(); m.paywall = .manual } label: {
                            Label(store.tier == .free ? L("home.upsell_free", MemberTier.annual.pricePerPeriod(store.price(.annual))) : L("home.upsell"), systemImage: "sparkles")
                                .font(Theme.body(.footnote).weight(.semibold)).engraved(Theme.gold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Spacer().frame(height: geo.size.height * 0.03)
                }
                .padding(.horizontal, 20).padding(.top, 8)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            if let msg = m.throwingMessage { ThrowAnimationView { m.throwingMessage = nil; m.toast = msg } }
            if let b = m.animatingPick { PickAnimationView { m.animatingPick = nil; m.picked = b } }
            if m.busy { ProgressView(L("home.searching")).font(Theme.body(.subheadline)).padding().glass(16) }
            if !didShowHook { FirstLaunchHookView(onWrite: { finishHook(); composing = true }, onLook: finishHook).transition(.opacity) }
        }
        .foregroundStyle(Theme.paper)
        .onAppear {
            if let uid = session.uid { m.start(uid: uid) { store.isMember } }
        }
        .onChange(of: store.tier) { _, _ in Task { await m.reloadQuota() } }
        .sheet(isPresented: $composing) { ThrowComposerView { msg in m.throwingMessage = msg; Task { await m.reloadQuota() } } }
        .fullScreenCover(item: $m.picked) { LetterView(bottle: $0) }
        .sheet(isPresented: $m.showAIFirst) { AIFirstVisitorView() }
        .sheet(item: $m.paywall) { PaywallView(reason: $0) }
        .alert(m.toast ?? "", isPresented: Binding(get: { m.toast != nil }, set: { if !$0 { m.toast = nil } })) { Button(L("common.ok")) {} }
    }

    private func finishHook() { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { didShowHook = true } }

    private var header: some View {
        TimelineView(.everyMinute) { tl in
            let phase = SkyPhase.at(tl.date)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(tl.date.formatted(.dateTime.weekday(.wide))) · \(phase.name)")
                    .font(Theme.body(.caption).weight(.semibold)).foregroundStyle(DayPart.at(tl.date).subtitleColor)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                Text(phase.title).font(Theme.title(.title)).foregroundStyle(Theme.engraved)
                    .shadow(color: .black.opacity(0.7), radius: 0, y: 2).shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.top, 6)
    }

    private func noticeCard(_ n: InAppNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: n.kind == "ai" ? "light.beacon.max.fill" : (n.event == "replied" ? "envelope.open.fill" : "person.fill"))
                .font(.footnote.weight(.bold)).stamped()
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.brassGradient).shadow(color: .black.opacity(0.5), radius: 3, y: 2))
            VStack(alignment: .leading, spacing: 2) {
                if n.kind == "ai" { HStack(spacing: 4) { AIBadge(); Text(AppConstants.aiName).font(Theme.body(.caption)).foregroundStyle(Theme.secondary) } }
                Text(n.message).font(Theme.body(.subheadline)).foregroundStyle(Theme.engraved).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button { Feel.tap(); if let uid = session.uid, let id = n.id { BottleService.shared.markRead(uid: uid, noticeId: id) } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).engraved().padding(6)
            }.accessibilityLabel(L("a11y.close_notice"))
        }
        .padding(12).woodPanel(18)
    }

    @ViewBuilder private func actionButtons(width: CGFloat) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        // v4：木板面板 + 顶部麻绳，两枚黄铜按钮，下方金币徽章显示今日剩余次数
        VStack(spacing: 12) {
            layout {
                Button { throwTapped() } label: { actionLabel(L("home.throw"), icon: "waterbottle.fill", sub: m.throwsLeft.map { L("home.throws_left", $0) } ?? L("common.unlimited")) }
                Button { pickTapped() } label: { actionLabel(L("home.pick"), icon: "basket.fill", sub: m.picksLeft.map { L("home.picks_left", $0) } ?? L("common.unlimited")) }
            }
            .buttonStyle(BrassButtonStyle(minHeight: 76))
            .disabled(m.throwingMessage != nil || m.animatingPick != nil || m.busy)
        }
        .padding(.horizontal, 14).padding(.top, 20).padding(.bottom, 16)
        .woodPanel(26, rope: true)
    }

    private func actionLabel(_ t: String, icon: String, sub: String) -> some View {
        VStack(spacing: 4) {
            Label(t, systemImage: icon).font(Theme.body(.headline).weight(.bold))
            Text(sub).font(Theme.body(.caption).weight(.medium)).opacity(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private func throwTapped() {
        Feel.tap()
        if let left = m.throwsLeft, left <= 0 { quotaExhausted(isThrow: true); return }
        composing = true
    }
    private func pickTapped() {
        Feel.tap()
        if let left = m.picksLeft, left <= 0 { quotaExhausted(isThrow: false); return }
        Task { await m.pick() }
    }
    /// 额度用完：非年卡用户展示会员页；新账号 24 小时限制与年卡防刷上限只提示
    private func quotaExhausted(isThrow: Bool) {
        Feel.warning()
        let newAccountLimited = isThrow && m.quota.throwLimit == AppConstants.newAccountDailyThrows
        if store.tier == .annual || newAccountLimited {
            m.toast = newAccountLimited ? L("home.new_account_limit", AppConstants.newAccountDailyThrows) : L("home.too_frequent")
        } else { m.paywall = .quotaExhausted }
    }
}

private struct OptionalGlass: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.glass() } else { content } }
}

/// 首次启动钩子：一句话 + 两个选择，只出现一次
struct FirstLaunchHookView: View {
    var onWrite: () -> Void
    var onLook: () -> Void
    @State private var appear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Theme.night.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Text(AppConstants.firstLaunchHook).font(Theme.title(.largeTitle)).multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 12)
                Text(L("first.body"))
                    .font(Theme.body(.body)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0)
                Spacer()
                Button(L("home.write"), action: { Feel.tap(); onWrite() }).buttonStyle(AmberButtonStyle())
                Button(L("first.look"), action: { Feel.tap(); onLook() }).buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 28).padding(.bottom, 24)
            .foregroundStyle(Theme.paper)
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 1.4).delay(0.3)) { appear = true } }
    }
}

struct ThrowComposerView: View {
    var onDone: (String) -> Void
    @EnvironmentObject var store: StoreService
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var style: BottleStyle = .classic
    @State private var sending = false
    @State private var error: String?
    @State private var paywall = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty { Text(L("compose.placeholder")).font(Theme.letter(.body)).foregroundStyle(Theme.ink.opacity(0.4)).padding(.top, 8).padding(.leading, 5) }
                        TextEditor(text: $text).font(Theme.letter(.body)).foregroundStyle(Theme.ink).scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .onChange(of: text) { _, v in if v.count > AppConstants.maxBottleChars { text = String(v.prefix(AppConstants.maxBottleChars)) } }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 34).background(LetterPaper(style: style))
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(text.count)/\(AppConstants.maxBottleChars)").font(Theme.body(.caption).monospacedDigit())
                            .foregroundStyle(text.count >= AppConstants.maxBottleChars ? Color(hex: 0x9C1C26) : Theme.parchFaint)
                            .padding(.trailing, 30).padding(.bottom, 22)
                            .accessibilityLabel("\(text.count)/\(AppConstants.maxBottleChars)")
                    }

                    Text(L("compose.style")).font(Theme.body(.subheadline).weight(.semibold)).engraved()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(BottleStyle.allCases) { s in
                                Button { Feel.select(); if s.exclusive && store.tier != .annual { paywall = true } else { style = s } } label: {
                                    // v4 样式木牌：年卡专属样式未解锁时显示黄铜锁
                                    VStack(spacing: 6) {
                                        Image("Parchment").resizable().colorMultiply(LetterPaper.tint(s)).frame(width: 40, height: 50)
                                            .overlay { if s.exclusive && store.tier != .annual {
                                                Image(systemName: "lock.fill").font(.caption.weight(.bold)).stamped()
                                                    .frame(width: 24, height: 24).background(Circle().fill(Theme.brassGradient))
                                            } }
                                        Text(s.title).font(Theme.body(.caption).weight(.semibold)).engraved()
                                    }
                                    .padding(10).frame(minWidth: 76)
                                    .woodPanel(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style == s ? Theme.gold : .clear, lineWidth: 2))
                                    .padding(.vertical, 4)
                                }.buttonStyle(.plain)
                                .accessibilityLabel(s.exclusive ? L("a11y.style_exclusive", s.title) : s.title)
                            }
                        }
                    }
                    PhotosPicker(selection: $item, matching: .images) { Label(image == nil ? L("compose.add_image") : L("compose.change_image"), systemImage: "photo") }
                        .font(Theme.body(.subheadline).weight(.semibold)).engraved(Theme.gold)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 12))
                        Button(L("compose.remove_image"), role: .destructive) { self.image = nil; item = nil }.font(Theme.body(.footnote))
                    }
                    if let error { Text(error).font(Theme.body(.footnote)).foregroundStyle(Color(hex: 0xFF8A80)) }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button { send() } label: { Label(sending ? L("compose.sending") : L("compose.send"), systemImage: "seal.fill") }
                    .buttonStyle(BrassButtonStyle())
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .foregroundStyle(Theme.paper)
            .background(Image("OceanNight").resizable().scaledToFill().overlay(Color.black.opacity(0.35)).ignoresSafeArea())
            .navigationTitle(L("home.write")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ImagePaint(image: Image("Wood"), scale: 0.3), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
            }
            .onChange(of: item) { _, it in Task { if let d = try? await it?.loadTransferable(type: Data.self) { image = UIImage(data: d) } } }
            .sheet(isPresented: $paywall) { PaywallView(reason: .manual) }
        }
        .tint(Theme.gold)
    }
    func send() {
        sending = true; Feel.tap()
        Task { defer { sending = false }
            do { let msg = try await BottleService.shared.throwBottle(text: text, image: image, style: style); onDone(msg); dismiss() }
            catch { self.error = error.localizedDescription; Feel.warning() }
        }
    }
}

/// 举报原因：本地化键（举报记录里保存键，便于跨语言统计）
enum ReportReason { static let all = ["report.sexual", "report.spam", "report.scam", "report.harass", "report.other"] }

struct AIFirstVisitorView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "light.beacon.max.fill").font(.largeTitle).imageScale(.large).foregroundStyle(.yellow)
            HStack { Text(AppConstants.aiName).font(.title2.bold()); Text("AI").font(.caption.bold()).padding(4).background(.orange, in: Capsule()) }
            Text(AppConstants.firstVisitorText).multilineTextAlignment(.center)
            Text(L("ai.notice_full")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L("common.gotit")) { dismiss() }.buttonStyle(.borderedProminent)
            // TODO 下一批：AI 聊天界面（消息气泡始终带「AI」标签）
        }.padding(32).presentationDetents([.medium])
    }
}

struct MyBottlesView: View {
    @EnvironmentObject var session: SessionStore
    @State private var bottles: [Bottle] = []
    @State private var l: ListenerRegistration?
    var body: some View {
        NavigationStack {
            List(bottles) { b in
                VStack(alignment: .leading, spacing: 6) {
                    Text(b.text).lineLimit(2)
                    if !b.replierIds.isEmpty { Text(L("bottles.replies", b.replierIds.count)).font(.caption).foregroundStyle(.green) }
                    HStack {
                        Text(b.status.title).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color(b.status).opacity(0.25), in: Capsule())
                        if b.status == .aiReplied { Text("AI").font(.caption2.bold()).foregroundStyle(.orange) }
                        Spacer()
                        Text(b.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if bottles.isEmpty { ContentUnavailableView(L("bottles.empty"), systemImage: "water.waves") } }
            .navigationTitle(L("bottles.title"))
        }
        .onAppear { if let uid = session.uid, l == nil { l = BottleService.shared.listenMyBottles(uid: uid) { bottles = $0 } } }
        .onDisappear { l?.remove(); l = nil }
    }
    func color(_ s: BottleStatus) -> Color {
        switch s { case .replied, .kept: .green; case .thrownBack: .gray; case .viewedNoReply: .orange; case .aiReplied: .yellow; default: .blue }
    }
}


struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var store: StoreService
    @ObservedObject private var sfx = SoundFX.shared
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var newName = ""
    @State private var paywall = false
    var body: some View {
        NavigationStack {
            Form {
                if let p = session.profile {
                    Section(L("settings.profile")) { LabeledContent(L("onb.nickname"), value: p.nickname); LabeledContent(L("onb.gender"), value: p.gender.title); LabeledContent(L("onb.age"), value: "\(p.currentAge)")
                        Button(L("settings.rename")) { newName = p.nickname; editing = true } }
                }
                Section(L("settings.membership")) {
                    LabeledContent(L("settings.current"), value: store.tier.title)
                    LabeledContent(L("settings.daily"), value: store.tier.quotaText)
                    Button(store.tier == .annual ? L("settings.view_perks") : L("settings.upgrade")) { paywall = true }
                    Button(L("store.restore")) { Task { await store.restore() } }
                    Button(L("store.manage")) { Task { if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene { try? await AppStore.showManageSubscriptions(in: s) } } }
                }
                Section(L("settings.sound")) { Toggle(L("settings.sfx"), isOn: $sfx.enabled) }
                Section { Button(L("settings.delete"), role: .destructive) { confirmDelete = true } }
                    footer: { Text(L("settings.footer")) }
                if let e = session.error { Text(e).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden).background(Theme.night.ignoresSafeArea())
            .navigationTitle(L("tab.me"))
            .sheet(isPresented: $paywall) { PaywallView(reason: .manual) }
            .alert(L("settings.delete_confirm"), isPresented: $confirmDelete) {
                Button(L("settings.delete_btn"), role: .destructive) { Task { await session.deleteAccount() } }
                Button(L("common.cancel"), role: .cancel) {}
            } message: { Text(L("settings.delete_msg")) }
            .alert(L("settings.rename"), isPresented: $editing) {
                TextField(L("settings.name_hint"), text: $newName)
                Button(L("common.save")) { Task { await session.updateNickname(newName) } }
                Button(L("common.cancel"), role: .cancel) {}
            }
        }
    }
}
