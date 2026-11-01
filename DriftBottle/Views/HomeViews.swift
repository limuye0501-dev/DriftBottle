import SwiftUI
import PhotosUI
import FirebaseFirestore
import StoreKit

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("海边", systemImage: "water.waves") }
            ChatListView().tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
            MyBottlesView().tabItem { Label("瓶子", systemImage: "rectangle.stack") }
            SettingsView().tabItem { Label("我", systemImage: "person") }
        }
        .tint(Theme.amber)
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
        l = BottleService.shared.listenNotices(uid: uid) { [weak self] list in
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
        }
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

    var body: some View {
        ZStack {
            NightBeachBackground()
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(m.notices.prefix(typeSize.isAccessibilitySize ? 1 : 2)) { noticeCard($0) }
                    Spacer(minLength: 8)
                    actionButtons(width: geo.size.width)
                    if store.tier != .annual {
                        Button { Feel.tap(); m.paywall = .manual } label: {
                            Label(store.tier == .free ? "年卡 \(store.price(.annual))/年 · 不限次数 · 专属瓶子" : "升级年卡 · 不限次数", systemImage: "sparkles")
                                .font(Theme.body(.footnote)).foregroundStyle(Theme.amber)
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
            if m.busy { ProgressView("正在海里摸索…").font(Theme.body(.subheadline)).padding().glass(16) }
            if !didShowHook { FirstLaunchHookView(onWrite: { finishHook(); composing = true }, onLook: finishHook).transition(.opacity) }
        }
        .foregroundStyle(Theme.paper)
        .onAppear {
            if let uid = session.uid { m.start(uid: uid) { store.isMember } }
            SoundFX.shared.startAmbient()
        }
        .onDisappear { SoundFX.shared.stopAmbient() }
        .onChange(of: store.tier) { _, _ in Task { await m.reloadQuota() } }
        .sheet(isPresented: $composing) { ThrowComposerView { msg in m.throwingMessage = msg; Task { await m.reloadQuota() } } }
        .fullScreenCover(item: $m.picked) { LetterView(bottle: $0) }
        .sheet(isPresented: $m.showAIFirst) { AIFirstVisitorView() }
        .sheet(item: $m.paywall) { PaywallView(reason: $0) }
        .alert(m.toast ?? "", isPresented: Binding(get: { m.toast != nil }, set: { if !$0 { m.toast = nil } })) { Button("好") {} }
    }

    private func finishHook() { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { didShowHook = true } }

    private var header: some View {
        TimelineView(.everyMinute) { tl in
            let phase = SkyPhase.at(tl.date)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(tl.date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))) · \(phase.name)")
                    .font(Theme.body(.caption)).foregroundStyle(Theme.secondary)
                Text(phase.title).font(Theme.title(.title)).foregroundStyle(Theme.paper)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.top, 6)
    }

    private func noticeCard(_ n: InAppNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(n.kind == "ai" ? Theme.amber : Color(hex: 0x3B4A7A)).frame(width: 30, height: 30)
                Image(systemName: n.kind == "ai" ? "light.beacon.max.fill" : (n.event == "replied" ? "envelope.open.fill" : "person.fill"))
                    .font(.footnote).foregroundStyle(n.kind == "ai" ? Theme.ink : Theme.paper)
            }
            VStack(alignment: .leading, spacing: 2) {
                if n.kind == "ai" { HStack(spacing: 4) { AIBadge(); Text(AppConstants.aiName).font(Theme.body(.caption)).foregroundStyle(Theme.secondary) } }
                Text(n.message).font(Theme.body(.subheadline)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button { Feel.tap(); if let uid = session.uid, let id = n.id { BottleService.shared.markRead(uid: uid, noticeId: id) } } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(Theme.tertiary).padding(6)
            }.accessibilityLabel("关闭通知")
        }
        .padding(12).glass(18)
    }

    @ViewBuilder private func actionButtons(width: CGFloat) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button { throwTapped() } label: {
                actionLabel("扔一个瓶子", icon: "envelope.fill", sub: m.throwsLeft.map { "今晚还能写 \($0) 封" } ?? "不限次数", filled: true)
            }
            Button { pickTapped() } label: {
                actionLabel("捡一个瓶子", icon: "hand.raised.fill", sub: m.picksLeft.map { "还能捡 \($0) 次" } ?? "不限次数", filled: false)
            }
        }
        .buttonStyle(.plain)
        .disabled(m.throwingMessage != nil || m.animatingPick != nil || m.busy)
    }

    private func actionLabel(_ t: String, icon: String, sub: String, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.title3)
            Spacer(minLength: 6)
            Text(t).font(Theme.body(.headline).weight(.semibold))
            Text(sub).font(Theme.body(.caption)).opacity(0.75)
        }
        .foregroundStyle(filled ? Theme.ink : Theme.paper)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            if filled { RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.amberGradient).shadow(color: Theme.amber.opacity(0.35), radius: 18, y: 8) }
        }
        .modifier(OptionalGlass(on: !filled))
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
        .accessibilityElement(children: .combine)
    }

    private func throwTapped() {
        Feel.tap()
        if let left = m.throwsLeft, left <= 0 { quotaExhausted("扔瓶"); return }
        composing = true
    }
    private func pickTapped() {
        Feel.tap()
        if let left = m.picksLeft, left <= 0 { quotaExhausted("捡瓶"); return }
        Task { await m.pick() }
    }
    /// 额度用完：非年卡用户展示会员页；新账号 24 小时限制与年卡防刷上限只提示
    private func quotaExhausted(_ what: String) {
        Feel.warning()
        let newAccountLimited = what == "扔瓶" && m.quota.throwLimit == AppConstants.newAccountDailyThrows
        if store.tier == .annual || newAccountLimited {
            m.toast = newAccountLimited ? "新账号首日每天最多扔 \(AppConstants.newAccountDailyThrows) 个瓶子，明天就恢复正常啦" : "今天扔得太频繁了，休息一下，明天再来吧"
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
                Text("把说不出口的话装进瓶子，\n交给今晚的海。会有一个同样醒着的人捡到它。")
                    .font(Theme.body(.body)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0)
                Spacer()
                Button("写一个瓶子", action: { Feel.tap(); onWrite() }).buttonStyle(AmberButtonStyle())
                Button("先看看海", action: { Feel.tap(); onLook() }).buttonStyle(GlassButtonStyle())
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
                        if text.isEmpty { Text("写给一个陌生人…").font(Theme.letter(.body)).foregroundStyle(Theme.ink.opacity(0.4)).padding(.top, 8).padding(.leading, 5) }
                        TextEditor(text: $text).font(Theme.letter(.body)).foregroundStyle(Theme.ink).scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .onChange(of: text) { _, v in if v.count > AppConstants.maxBottleChars { text = String(v.prefix(AppConstants.maxBottleChars)) } }
                    }
                    .padding(14).background(LetterPaper(style: style)).clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("\(text.count)/\(AppConstants.maxBottleChars)").font(Theme.body(.caption)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .trailing)

                    Text("瓶子样式").font(Theme.body(.subheadline).weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(BottleStyle.allCases) { s in
                                Button { Feel.select(); if s.exclusive && store.tier != .annual { paywall = true } else { style = s } } label: {
                                    VStack(spacing: 6) {
                                        Circle().fill(LetterPaper.tint(s)).frame(width: 34, height: 34)
                                            .overlay(Circle().strokeBorder(style == s ? Theme.amber : .clear, lineWidth: 2))
                                        HStack(spacing: 2) { Text(s.title); if s.exclusive && store.tier != .annual { Image(systemName: "lock.fill") } }
                                            .font(Theme.body(.caption))
                                    }.padding(8)
                                }.buttonStyle(.plain)
                                .accessibilityLabel(s.exclusive ? "\(s.title)，年卡专属" : s.title)
                            }
                        }
                    }
                    PhotosPicker(selection: $item, matching: .images) { Label(image == nil ? "放一张图片（可选）" : "更换图片", systemImage: "photo") }
                        .font(Theme.body(.subheadline)).foregroundStyle(Theme.amber)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 12))
                        Button("移除图片", role: .destructive) { self.image = nil; item = nil }.font(Theme.body(.footnote))
                    }
                    if let error { Text(error).font(Theme.body(.footnote)).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .foregroundStyle(Theme.paper)
            .background(Theme.deep.ignoresSafeArea())
            .navigationTitle("写一个瓶子").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(sending ? "扔出中…" : "扔向大海") { send() }.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onChange(of: item) { _, it in Task { if let d = try? await it?.loadTransferable(type: Data.self) { image = UIImage(data: d) } } }
            .sheet(isPresented: $paywall) { PaywallView(reason: .manual) }
        }
        .tint(Theme.amber)
    }
    func send() {
        sending = true; Feel.tap()
        Task { defer { sending = false }
            do { let msg = try await BottleService.shared.throwBottle(text: text, image: image, style: style); onDone(msg); dismiss() }
            catch { self.error = error.localizedDescription; Feel.warning() }
        }
    }
}

enum ReportReason { static let all = ["色情低俗", "广告/引流（微信、QQ、二维码）", "诈骗", "骚扰辱骂", "其他"] }

struct AIFirstVisitorView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "light.beacon.max.fill").font(.largeTitle).imageScale(.large).foregroundStyle(.yellow)
            HStack { Text(AppConstants.aiName).font(.title2.bold()); Text("AI").font(.caption.bold()).padding(4).background(.orange, in: Capsule()) }
            Text(AppConstants.firstVisitorText).multilineTextAlignment(.center)
            Text("灯塔守望者是 AI 陪伴角色，不是真实用户。一旦有其他旅人来到这片海，你的瓶子就会漂向真实的人。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("好的") { dismiss() }.buttonStyle(.borderedProminent)
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
                    if !b.replierIds.isEmpty { Text("\(b.replierIds.count) 位真人回复了你").font(.caption).foregroundStyle(.green) }
                    HStack {
                        Text(b.status.title).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(color(b.status).opacity(0.25), in: Capsule())
                        if b.status == .aiReplied { Text("AI").font(.caption2.bold()).foregroundStyle(.orange) }
                        Spacer()
                        Text(b.createdAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "zh_CN")))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if bottles.isEmpty { ContentUnavailableView("还没有扔过瓶子", systemImage: "water.waves") } }
            .navigationTitle("我的瓶子")
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
                    Section("资料") { LabeledContent("昵称", value: p.nickname); LabeledContent("性别", value: p.gender.title); LabeledContent("年龄", value: "\(p.currentAge)")
                        Button("修改昵称") { newName = p.nickname; editing = true } }
                }
                Section("会员") {
                    LabeledContent("当前", value: store.tier.title)
                    LabeledContent("每日次数", value: store.tier.quotaText)
                    Button(store.tier == .annual ? "查看会员权益" : "开通 / 升级会员") { paywall = true }
                    Button("恢复购买") { Task { await store.restore() } }
                    Button("管理订阅") { Task { if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene { try? await AppStore.showManageSubscriptions(in: s) } } }
                }
                Section("声音") { Toggle("海浪与音效", isOn: $sfx.enabled) }
                Section { Button("注销账号", role: .destructive) { confirmDelete = true } }
                    footer: { Text("本应用无需注册，账号仅保存在本机。卸载重装后将以新身份进入，旧聊天无法找回。") }
                if let e = session.error { Text(e).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden).background(Theme.night.ignoresSafeArea())
            .navigationTitle("我")
            .sheet(isPresented: $paywall) { PaywallView(reason: .manual) }
            .alert("确定注销账号？", isPresented: $confirmDelete) {
                Button("注销", role: .destructive) { Task { await session.deleteAccount() } }
                Button("取消", role: .cancel) {}
            } message: { Text("你的资料、瓶子和聊天记录将被永久删除，且无法恢复") }
            .alert("修改昵称", isPresented: $editing) {
                TextField("1–12 个字", text: $newName)
                Button("保存") { Task { await session.updateNickname(newName) } }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
