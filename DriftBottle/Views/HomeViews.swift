import SwiftUI
import PhotosUI
import FirebaseFirestore
import StoreKit

struct NightBeachBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.04, blue: 0.15), Color(red: 0.05, green: 0.12, blue: 0.3)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<80 {
                    let p = CGPoint(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height * 0.5, using: &rng))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.7)))
                }
            }
            Circle().fill(Color.yellow.opacity(0.85)).frame(width: 60).blur(radius: 1).offset(x: 110, y: -280)
            VStack { Spacer()
                Rectangle().fill(LinearGradient(colors: [Color(red: 0.05, green: 0.2, blue: 0.4), Color(red: 0.1, green: 0.3, blue: 0.5)], startPoint: .top, endPoint: .bottom)).frame(height: 220)
                Rectangle().fill(Color(red: 0.55, green: 0.48, blue: 0.36)).frame(height: 90)
            }
        }.ignoresSafeArea()
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("海边", systemImage: "water.waves") }
            ChatListView().tabItem { Label("聊天", systemImage: "bubble.left.and.bubble.right") }
            MyBottlesView().tabItem { Label("我的瓶子", systemImage: "list.bullet") }
            SettingsView().tabItem { Label("我的", systemImage: "person") }
        }
    }
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var throwsUsed = 0, picksUsed = 0
    @Published var notices: [InAppNotice] = []
    @Published var toast: String?
    @Published var picked: Bottle?
    @Published var showAIFirst = false
    @Published var busy = false
    private var l: ListenerRegistration?
    func start(uid: String) {
        Task { let u = await QuotaService.usage(uid: uid); throwsUsed = u.throws; picksUsed = u.picks }
        l = BottleService.shared.listenNotices(uid: uid) { [weak self] in self?.notices = $0 }
    }
    func pick(limit: Int) async {
        guard picksUsed < limit else { toast = "今天的捡瓶次数用完了（\(limit) 次）"; return }
        busy = true; defer { busy = false }
        do {
            let r = try await BottleService.shared.pickBottle()
            picksUsed += 1
            if r.isAIFirstVisitor { showAIFirst = true } else if let b = r.bottle { picked = b } else { toast = r.message }
        } catch { toast = error.localizedDescription }
    }
}

struct HomeView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var store: StoreService
    @StateObject private var m = HomeModel()
    @State private var composing = false
    @State private var paywall = false
    var limit: Int { QuotaService.limit(isMember: store.isMember || (session.profile?.isMember ?? false)) }
    var body: some View {
        ZStack {
            NightBeachBackground()
            VStack(spacing: 16) {
                ForEach(m.notices) { n in
                    HStack { Image(systemName: n.kind == "ai" ? "light.beacon.max.fill" : "person.fill")
                        if n.kind == "ai" { Text("AI").font(.caption2.bold()).padding(3).background(.orange, in: Capsule()) }
                        Text(n.message).font(.subheadline); Spacer()
                        Button { if let uid = session.uid, let id = n.id { BottleService.shared.markRead(uid: uid, noticeId: id) } } label: { Image(systemName: "xmark") } }
                    .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
                Text("今晚的海很安静").font(.title3).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 24) {
                    beachButton("扔一个", icon: "paperplane.fill", left: limit - m.throwsUsed) {
                        if m.throwsUsed >= limit { store.isMember ? (m.toast = "今天的扔瓶次数用完了") : (paywall = true) } else { composing = true }
                    }
                    beachButton("捡一个", icon: "hand.raised.fill", left: limit - m.picksUsed) {
                        if m.picksUsed >= limit && !store.isMember { paywall = true } else { Task { await m.pick(limit: limit) } }
                    }
                }
                if !store.isMember { Button("开通年度会员，每天 30 次 · \(store.priceText)/年") { paywall = true }.font(.footnote) }
                Spacer().frame(height: 60)
            }.padding()
            if m.busy { ProgressView("正在海里摸索…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)) }
        }
        .onAppear { if let uid = session.uid { m.start(uid: uid) } }
        .sheet(isPresented: $composing) { ThrowComposerView { m.throwsUsed += 1; m.toast = $0 } }
        .sheet(item: $m.picked) { PickedBottleView(bottle: $0) }
        .sheet(isPresented: $m.showAIFirst) { AIFirstVisitorView() }
        .sheet(isPresented: $paywall) { PaywallView() }
        .alert(m.toast ?? "", isPresented: Binding(get: { m.toast != nil }, set: { if !$0 { m.toast = nil } })) { Button("好") {} }
    }
    func beachButton(_ t: String, icon: String, left: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack { Image(systemName: icon).font(.title); Text(t).bold(); Text("今日剩余 \(max(0, left))").font(.caption2) }
                .frame(width: 120, height: 110).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }.foregroundStyle(.white)
    }
}

struct ThrowComposerView: View {
    var onDone: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var sending = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { TextEditor(text: $text).frame(minHeight: 160)
                        .onChange(of: text) { _, v in if v.count > AppConstants.maxBottleChars { text = String(v.prefix(AppConstants.maxBottleChars)) } } }
                    footer: { Text("\(text.count)/\(AppConstants.maxBottleChars)") }
                Section("图片（可选，1 张）") {
                    PhotosPicker(image == nil ? "选择图片" : "更换图片", selection: $item, matching: .images)
                    if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                        Button("移除图片", role: .destructive) { self.image = nil; item = nil } }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("写一个瓶子")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(sending ? "扔出中…" : "扔向大海") { send() }.disabled(sending || text.isEmpty) }
            }
            .onChange(of: item) { _, it in Task { if let d = try? await it?.loadTransferable(type: Data.self) { image = UIImage(data: d) } } }
        }
    }
    func send() {
        sending = true
        Task { defer { sending = false }
            do { let msg = try await BottleService.shared.throwBottle(text: text, image: image); onDone(msg); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct PickedBottleView: View {
    let bottle: Bottle
    @Environment(\.dismiss) var dismiss
    @State private var kept = false
    @State private var reply = ""
    @State private var error: String?
    @State private var reportSheet = false
    @State private var working = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("来自 \(bottle.senderNickname) 的瓶子").font(.headline)
                    Text(bottle.text).font(.body)
                    if let u = bottle.imageURL, let url = URL(string: u) {
                        AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }.clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text("已有 \(bottle.replierIds.count)/\(AppConstants.maxRepliers) 人回复").font(.caption).foregroundStyle(.secondary)
                    if kept {
                        TextField("写下你的回复，开启聊天（免费）", text: $reply, axis: .vertical).textFieldStyle(.roundedBorder)
                        Button("发送回复") { act { _ = try await BottleService.shared.reply(bottle.id!, text: reply) } }
                            .buttonStyle(.borderedProminent).disabled(working || reply.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Text("保留它，就能给对方回信；放走它，它会继续漂向下一位旅人").font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button("放走") { act { try await BottleService.shared.release(bottle.id!) } }.buttonStyle(.bordered)
                            Spacer()
                            Button("保留") { Task { working = true; defer { working = false }
                                do { try await BottleService.shared.keep(bottle.id!); kept = true } catch { self.error = error.localizedDescription } } }
                                .buttonStyle(.borderedProminent)
                        }.disabled(working)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding()
            }
            .navigationTitle("捡到一个瓶子")
            .toolbar { ToolbarItem { Menu { Button("举报") { reportSheet = true }
                Button("拉黑", role: .destructive) { act { try await UserService.shared.block(bottle.senderId); try? await BottleService.shared.release(bottle.id!) } } } label: { Image(systemName: "ellipsis.circle") } } }
            .confirmationDialog("举报原因", isPresented: $reportSheet) {
                ForEach(ReportReason.all, id: \.self) { r in
                    Button(r) { act { try await UserService.shared.report(targetUserId: bottle.senderId, bottleId: bottle.id, reason: r); try? await BottleService.shared.release(bottle.id!) } }
                }
            }
            .interactiveDismissDisabled()  // 必须选择保留或放走
        }
    }
    func act(_ f: @escaping () async throws -> Void) {
        Task { working = true; defer { working = false }
            do { try await f(); dismiss() } catch { self.error = error.localizedDescription } }
    }
}

enum ReportReason { static let all = ["色情低俗", "广告/引流（微信、QQ、二维码）", "诈骗", "骚扰辱骂", "其他"] }

struct AIFirstVisitorView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "light.beacon.max.fill").font(.system(size: 56)).foregroundStyle(.yellow)
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

struct PaywallView: View {
    @EnvironmentObject var store: StoreService
    @Environment(\.dismiss) var dismiss
    @State private var err: String?
    @State private var buying = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("年度会员").font(.title.bold())
                Text("价格：\(store.priceText)/年（约 ¥8.2/月），按年自动续期").font(.headline)
                Group {
                    Label("每天可扔瓶 30 次、捡瓶 30 次（免费用户各 8 次）", systemImage: "checkmark.circle")
                    Label("仅此而已——我们不出售“优先曝光”或“查看谁看过我”", systemImage: "checkmark.circle")
                }
                Text("永久免费：保留瓶子、回复、聊天、发图片、举报与拉黑都不收费。").font(.subheadline).foregroundStyle(.green)
                Text("""
                自动续期说明：确认购买后将从你的 Apple ID 账户扣款。订阅到期前 24 小时内会自动续订并扣费 \(store.priceText)，除非你在到期前至少 24 小时关闭自动续期。
                如何取消：打开 iPhone「设置」→ 点击你的 Apple ID → 「订阅」→ 选择「漂流瓶」→「取消订阅」。取消后会员权益保留到当期结束。
                """).font(.footnote).foregroundStyle(.secondary)
                Button(buying ? "处理中…" : "\(store.priceText)/年 开通") {
                    Task { buying = true; defer { buying = false }
                        do { try await store.purchase(); if store.isMember { dismiss() } } catch { err = error.localizedDescription } }
                }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(buying)
                HStack {
                    Button("恢复购买") { Task { await store.restore() } }
                    Spacer()
                    Button("管理订阅") { Task { if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene { try? await AppStore.showManageSubscriptions(in: s) } } }
                }.font(.footnote)
                if let e = err ?? store.lastError { Text(e).foregroundStyle(.red).font(.footnote) }
            }.padding()
        }.presentationDetents([.large])
    }
}

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                if let p = session.profile {
                    Section("资料") { LabeledContent("昵称", value: p.nickname); LabeledContent("性别", value: p.gender.title); LabeledContent("年龄", value: "\(p.age)") }
                }
                Section { Button("退出登录") { session.signOut() }
                    Button("注销账号", role: .destructive) { confirmDelete = true } }
                if let e = session.error { Text(e).foregroundStyle(.red) }
            }
            .navigationTitle("我的")
            .alert("确定注销账号？", isPresented: $confirmDelete) {
                Button("注销", role: .destructive) { Task { await session.deleteAccount() } }
                Button("取消", role: .cancel) {}
            } message: { Text("你的资料、瓶子和聊天记录将被永久删除，且无法恢复") }
        }
    }
}
