import SwiftUI
import PhotosUI
import FirebaseFirestore

struct ChatListView: View {
    @EnvironmentObject var session: SessionStore
    @State private var chats: [Chat] = []
    @State private var l: ListenerRegistration?
    var body: some View {
        NavigationStack {
            List(chats) { c in
                NavigationLink(value: c.id ?? "") {
                    HStack {
                        Image(systemName: c.isAI ? "light.beacon.max.fill" : "person.fill").font(.body)
                            .foregroundStyle(c.isAI ? Theme.ink : Theme.paper)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(c.isAI ? AnyShapeStyle(Theme.amberGradient) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4FA3A5), Color(hex: 0x2A4F7A)], startPoint: .top, endPoint: .bottom))))
                        VStack(alignment: .leading) {
                            HStack { Text(title(c)).font(Theme.body(.headline)); if c.isAI { AIBadge() } }
                            Text(c.blocked ? L("chat.closed") : (c.lastMessage.isEmpty ? L("chat.image") : c.lastMessage)).font(Theme.body(.subheadline)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.04))
            }
            .navigationDestination(for: String.self) { id in
                if let c = chats.first(where: { $0.id == id }) { ChatView(chat: c) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night.ignoresSafeArea())
            .overlay { if chats.isEmpty { ContentUnavailableView(L("chat.empty_title"), systemImage: "bubble.left", description: Text(L("chat.empty_desc"))) } }
            .navigationTitle(L("chat.title"))
        }
        .onAppear { if let uid = session.uid, l == nil { l = ChatService.shared.listenChats(uid: uid) { chats = $0 } } }
        .onDisappear { l?.remove(); l = nil }
    }
    func title(_ c: Chat) -> String {
        if c.isAI { return AppConstants.aiName }
        let other = c.participants.first { $0 != session.uid } ?? ""
        return c.names[other].flatMap { $0.isEmpty ? nil : $0 } ?? L("chat.unknown")
    }
}


struct ChatView: View {
    let chat: Chat
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var l: ListenerRegistration?
    @State private var text = ""
    @State private var item: PhotosPickerItem?
    @State private var sending = false
    @State private var error: String?
    @State private var reportSheet = false
    @State private var confirmBlock = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var otherId: String { chat.participants.first { $0 != session.uid } ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            if chat.isAI {
                HStack { AIBadge(); Text(L("ai.disclaimer")).font(Theme.body(.caption)) }
                    .frame(maxWidth: .infinity).padding(8).background(Theme.amber.opacity(0.15))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let origin = messages.first, origin.text.hasPrefix("【瓶子】") { originCard(origin) }
                        ForEach(messages.filter { !$0.text.hasPrefix("【瓶子】") }) { bubble($0).id($0.id) }
                    }.padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { old, _ in
                    if old > 0, let last = messages.last, last.senderId != session.uid { Feel.received() }
                    if let last = messages.last?.id { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
            if let error { Text(error).font(Theme.body(.caption)).foregroundStyle(.red) }
            if chat.blocked {
                Text(L("chat.closed")).foregroundStyle(Theme.secondary).padding()
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $item, matching: .images) {
                        Image(systemName: "photo").font(.body).foregroundStyle(Theme.secondary).frame(width: 36, height: 36)
                    }.disabled(sending).accessibilityLabel(L("a11y.send_image"))
                    TextField(L("chat.placeholder"), text: $text, axis: .vertical).font(Theme.body(.body)).lineLimit(1...5)
                        .padding(.vertical, 8)
                    Button { send(image: nil) } label: {
                        Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(Theme.ink)
                            .frame(width: 36, height: 36).background(Circle().fill(Theme.amberGradient))
                    }
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(L("a11y.send"))
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .glass(26)
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .foregroundStyle(Theme.paper)
        .background(LinearGradient(colors: [Theme.deep, Theme.night], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle(chat.isAI ? AppConstants.aiName : (chat.names[otherId] ?? L("chat.default_title")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !chat.isAI {
                ToolbarItem { Menu {
                    Button(L("common.report")) { reportSheet = true }
                    Button(L("common.block"), role: .destructive) { confirmBlock = true }
                } label: { Image(systemName: "ellipsis.circle") } }
            }
        }
        .confirmationDialog(L("report.title"), isPresented: $reportSheet) {
            ForEach(ReportReason.all, id: \.self) { r in
                Button(L(r)) { Task { try? await UserService.shared.report(targetUserId: otherId, bottleId: chat.bottleId, reason: r) ; error = L("report.thanks") } }
            }
        }
        .alert(L("block.confirm"), isPresented: $confirmBlock) {
            Button(L("common.block"), role: .destructive) { Task { do { try await ChatService.shared.blockInChat(chatId: chat.id ?? "", otherId: otherId); dismiss() } catch { self.error = error.localizedDescription } } }
            Button(L("common.cancel"), role: .cancel) {}
        }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { send(image: img) }; item = nil }
        }
        .onAppear { if l == nil, let id = chat.id { l = ChatService.shared.listenMessages(chatId: id) { messages = $0 } } }
        .onDisappear { l?.remove(); l = nil }
    }

    /// 置顶：这段对话源自哪个瓶子
    func originCard(_ m: ChatMessage) -> some View {
        Label { Text(L("chat.origin", m.text.replacingOccurrences(of: "【瓶子】", with: ""))).lineLimit(3) } icon: { Image(systemName: "envelope") }
            .font(Theme.letter(.footnote)).foregroundStyle(Theme.secondary)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).glass(14)
            .padding(.bottom, 6)
    }

    @ViewBuilder func bubble(_ m: ChatMessage) -> some View {
        let mine = m.senderId == session.uid
        HStack {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if m.isAI { HStack(spacing: 4) { AIBadge(); Text(AppConstants.aiName).font(Theme.body(.caption2)).foregroundStyle(Theme.secondary) } }
                if let u = m.imageURL, let url = URL(string: u) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxWidth: 220, maxHeight: 280)   // 外层 Spacer 保证在 mini 上也不超宽
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if m.hidden == true || !m.text.isEmpty {
                    Text(m.hidden == true ? L("chat.hidden") : m.text).font(Theme.body(.body))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(mine ? Theme.ink : Theme.paper)
                        .background {
                            if mine { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.amberGradient) }
                            else if m.isAI { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.amber.opacity(0.18)) }
                            else { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial) }
                        }
                        .textSelection(.enabled)
                }
            }
            if !mine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mine ? L("a11y.msg_me", m.text) : (m.isAI ? L("a11y.msg_ai", AppConstants.aiName, m.text) : L("a11y.msg_other", m.text)))
    }

    func send(image: UIImage?) {
        guard let id = chat.id else { return }
        let t = image == nil ? text : ""
        sending = true; error = nil
        Task { defer { sending = false }
            do { try await ChatService.shared.send(chatId: id, text: t, image: image); Feel.sent(); if image == nil { text = "" } }
            catch { self.error = error.localizedDescription }
        }
    }
}
