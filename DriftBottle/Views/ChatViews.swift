import SwiftUI
import PhotosUI
import FirebaseFirestore

struct ChatListView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var local = LocalSeaStore.shared
    @ObservedObject private var safety = SafetyStore.shared
    @State private var chats: [Chat] = []
    @State private var l: ListenerRegistration?
    private var shown: [Chat] {
        let extra = session.uid.map { local.chats(uid: $0, nickname: session.profile?.nickname ?? "") } ?? []
        let ids = Set(chats.compactMap(\.id))
        return (chats + extra.filter { !ids.contains($0.id ?? "") })
            .filter { c in
                let other = c.participants.first { $0 != session.uid } ?? ""
                return !safety.blocks(other)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        NavigationStack {
            List(shown) { c in
                NavigationLink(value: c.id ?? "") {
                    HStack {
                        Image(systemName: "person.fill").font(.body)
                            .foregroundStyle(Theme.paper)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x4FA3A5), Color(hex: 0x2A4F7A)], startPoint: .top, endPoint: .bottom)))
                        VStack(alignment: .leading) {
                            Text(title(c)).font(Theme.body(.headline))
                            Text(c.blocked ? L("chat.closed") : (c.lastMessage.isEmpty ? L("chat.image") : c.lastMessage)).font(Theme.body(.subheadline)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.04))
            }
            .navigationDestination(for: String.self) { id in
                if let c = shown.first(where: { $0.id == id }) { ChatView(chat: c) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night.ignoresSafeArea())
            .overlay { if shown.isEmpty { ContentUnavailableView(L("chat.empty_title"), systemImage: "bubble.left", description: Text(L("chat.empty_desc"))) } }
            .navigationTitle(L("chat.title"))
        }
        .onAppear {
            #if DEBUG
            if Demo.on { chats = Demo.chats; return }
            #endif
            if let uid = session.uid, l == nil { l = ChatService.shared.listenChats(uid: uid) { chats = $0.filter { !$0.isAI } } }
        }   // 旧 AI 会话隐藏
        .onDisappear { l?.remove(); l = nil }
    }
    func title(_ c: Chat) -> String {
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
    @State private var reportMessage: ChatMessage?
    @State private var confirmBlock = false
    @State private var confirmDelete: ChatMessage?
    @ObservedObject private var safety = SafetyStore.shared
    @ObservedObject private var local = LocalSeaStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var otherId: String { chat.participants.first { $0 != session.uid } ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let origin = messages.first, origin.isOrigin { originCard(origin) }
                        ForEach(messages.filter { !$0.isOrigin }) { bubble($0).id($0.id) }
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
                        Image(systemName: "photo").font(.body.weight(.semibold)).engraved().frame(width: 38, height: 38)
                    }.disabled(sending).accessibilityLabel(L("a11y.send_image"))
                    TextField(L("chat.placeholder"), text: $text, axis: .vertical).font(Theme.body(.body)).lineLimit(1...5)
                        .foregroundStyle(Theme.parchInk)
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .background(Color(hex: 0xF1E4C4), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.35)))
                    BrassKnob(systemImage: "paperplane.fill", label: L("a11y.send")) { send(image: nil) }
                        .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .woodPanel(0)
                .padding(.bottom, 0)
            }
        }
        .foregroundStyle(Theme.paper)
        .background(Image("OceanNight").resizable().scaledToFill().overlay(Color.black.opacity(0.3)).ignoresSafeArea())
        .toolbarBackground(ImagePaint(image: Image("Wood"), scale: 0.3), for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle(chat.names[otherId] ?? L("chat.default_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem { Menu {
                Button(L("letter.report")) { reportMessage = nil; reportSheet = true }
                Button(L("block.sender"), role: .destructive) { confirmBlock = true }
            } label: { Image(systemName: "ellipsis.circle") } }
        }
        .sheet(isPresented: $reportSheet) {
            ReportSheet(authorUid: reportMessage?.senderId ?? otherId, bottleId: chat.bottleId, messageId: reportMessage?.id, chatId: chat.id) {
                if let id = reportMessage?.id {
                    safety.hideMessage(id)
                    let chatId = chat.id ?? ""
                    let uid = session.uid ?? ""
                    if !chatId.hasPrefix("local"), !uid.isEmpty {
                        Task { try? await db.collection("chats").document(chatId).collection("messages").document(id).updateData(["hiddenFor": FieldValue.arrayUnion([uid])]) }
                    }
                }
                error = L("report.thanks")
                reportMessage = nil
            }
        }
        .alert(L("block.confirm"), isPresented: $confirmBlock) {
            Button(L("block.sender"), role: .destructive) {
                safety.rememberBlock(otherId)
                Task { do { try await ChatService.shared.blockInChat(chatId: chat.id ?? "", otherId: otherId); dismiss() } catch { self.error = error.localizedDescription } }
            }
            Button(L("common.cancel"), role: .cancel) {}
        }
        .alert(L("safety.delete_reply_confirm"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("settings.delete_btn"), role: .destructive) {
                if let m = confirmDelete, let id = m.id, let chatId = chat.id {
                    Task { try? await ChatService.shared.deleteOwnMessage(chatId: chatId, messageId: id) }
                }
                confirmDelete = nil
            }
            Button(L("common.cancel"), role: .cancel) { confirmDelete = nil }
        }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { send(image: img) }; item = nil }
        }
        .onAppear {
            #if DEBUG
            if Demo.on { messages = Demo.scene == "keeperchat" ? Demo.keeperMessages : Demo.messages; return }
            #endif
            if let id = chat.id, id.hasPrefix("local"), let uid = session.uid { messages = local.messages(uid: uid, chatId: id); return }
            if l == nil, let id = chat.id { l = ChatService.shared.listenMessages(chatId: id) { messages = $0 } }
        }
        .onChange(of: local.revision) { _, _ in
            if let id = chat.id, id.hasPrefix("local"), let uid = session.uid { messages = local.messages(uid: uid, chatId: id) }
        }
        .onDisappear { l?.remove(); l = nil }
    }

    /// 置顶：这段对话源自哪个瓶子
    func originCard(_ m: ChatMessage) -> some View {
        let body = displayText(m, origin: true)
        return VStack(alignment: .leading, spacing: 6) {
            Label { Text(L("chat.origin", body)).lineLimit(3) } icon: { Image(systemName: "envelope") }
                .font(Theme.letter(.footnote)).foregroundStyle(Theme.parchInk)
                .padding(.horizontal, 26).padding(.vertical, 22).frame(maxWidth: .infinity, alignment: .leading)
                .background(ParchmentScrap())
            safetyCapsules(m)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder func bubble(_ m: ChatMessage) -> some View {
        let mine = m.senderId == session.uid
        let text = displayText(m, origin: false)
        HStack {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if m.hidden != true, let u = m.imageURL, let url = URL(string: u), text != L("chat.hidden") {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxWidth: 220, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if m.hidden == true || !text.isEmpty {
                    Text(text).font(Theme.body(.body))
                        .textSelection(.enabled)
                        .modifier(BubbleSkin(mine: mine))
                }
                safetyCapsules(m)
            }
            if !mine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mine ? L("a11y.msg_me", text) : L("a11y.msg_other", text))
    }

    @ViewBuilder private func safetyCapsules(_ m: ChatMessage) -> some View {
        let mine = m.senderId == session.uid
        HStack(spacing: 10) {
            if mine {
                Button(L("safety.delete_reply")) { confirmDelete = m }
            } else {
                Button(L("chat.report_reply")) { reportMessage = m; reportSheet = true }
                Button(L("block.sender")) { confirmBlock = true }
            }
        }
        .font(Theme.body(.caption2).weight(.semibold))
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
    }

    private func displayText(_ m: ChatMessage, origin: Bool) -> String {
        let raw = origin ? m.originText : m.text
        if m.hidden == true { return L("chat.hidden") }
        if safety.hidesMessage(m.id) { return L("chat.hidden") }
        if let uid = session.uid, (m.hiddenFor ?? []).contains(uid) { return L("chat.hidden") }
        if !origin && m.senderId != session.uid && SensitiveWordFilter.contains(raw) { return L("chat.hidden") }
        if origin && SensitiveWordFilter.contains(raw) { return L("chat.hidden") }
        return raw
    }

    /// v4：我的消息 = 海玻璃；对方 = 九宫格羊皮纸碎片
    private struct BubbleSkin: ViewModifier {
        let mine: Bool
        func body(content: Content) -> some View {
            if mine {
                content.foregroundStyle(Color(hex: 0xEAF6FF)).padding(.horizontal, 14).padding(.vertical, 10).seaGlass()
            } else {
                content.foregroundStyle(Theme.parchInk).padding(.horizontal, 22).padding(.vertical, 18)
                    .frame(minWidth: 80, minHeight: 88).background(ParchmentScrap())
            }
        }
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
