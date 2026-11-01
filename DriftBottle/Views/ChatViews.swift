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
                        Image(systemName: c.isAI ? "light.beacon.max.fill" : "person.circle.fill").font(.title2)
                            .foregroundStyle(c.isAI ? .yellow : .blue)
                        VStack(alignment: .leading) {
                            HStack { Text(title(c)).bold(); if c.isAI { AIBadge() } }
                            Text(c.blocked ? "该聊天已关闭" : c.lastMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let c = chats.first(where: { $0.id == id }) { ChatView(chat: c) }
            }
            .overlay { if chats.isEmpty { ContentUnavailableView("还没有聊天", systemImage: "bubble.left", description: Text("保留并回复一个瓶子，就能开始聊天")) } }
            .navigationTitle("聊天")
        }
        .onAppear { if let uid = session.uid, l == nil { l = ChatService.shared.listenChats(uid: uid) { chats = $0 } } }
        .onDisappear { l?.remove(); l = nil }
    }
    func title(_ c: Chat) -> String {
        if c.isAI { return AppConstants.aiName }
        let other = c.participants.first { $0 != session.uid } ?? ""
        return c.names[other] ?? "漂流瓶旅人"
    }
}

struct AIBadge: View {
    var body: some View { Text("AI").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 2).background(.orange, in: Capsule()).foregroundStyle(.black) }
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
    var otherId: String { chat.participants.first { $0 != session.uid } ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            if chat.isAI {
                HStack { AIBadge(); Text("灯塔守望者是 AI 陪伴角色，不是真实用户").font(.caption) }
                    .frame(maxWidth: .infinity).padding(6).background(Color.orange.opacity(0.15))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) { ForEach(messages) { bubble($0).id($0.id) } }.padding()
                }
                .onChange(of: messages.count) { _, _ in if let last = messages.last?.id { withAnimation { proxy.scrollTo(last, anchor: .bottom) } } }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if chat.blocked {
                Text("该聊天已关闭").foregroundStyle(.secondary).padding()
            } else {
                HStack {
                    PhotosPicker(selection: $item, matching: .images) { Image(systemName: "photo") }.disabled(sending)
                    TextField("说点什么…", text: $text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                    Button("发送") { send(image: nil) }.disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding()
            }
        }
        .navigationTitle(chat.isAI ? AppConstants.aiName : (chat.names[otherId] ?? "聊天"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !chat.isAI {
                ToolbarItem { Menu {
                    Button("举报") { reportSheet = true }
                    Button("拉黑", role: .destructive) { confirmBlock = true }
                } label: { Image(systemName: "ellipsis.circle") } }
            }
        }
        .confirmationDialog("举报原因", isPresented: $reportSheet) {
            ForEach(ReportReason.all, id: \.self) { r in
                Button(r) { Task { try? await UserService.shared.report(targetUserId: otherId, bottleId: chat.bottleId, reason: r) ; error = "已收到举报，我们会尽快处理" } }
            }
        }
        .alert("拉黑后将无法再收到对方的瓶子和消息", isPresented: $confirmBlock) {
            Button("拉黑", role: .destructive) { Task { do { try await ChatService.shared.blockInChat(chatId: chat.id ?? "", otherId: otherId); dismiss() } catch { self.error = error.localizedDescription } } }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { send(image: img) }; item = nil }
        }
        .onAppear { if l == nil, let id = chat.id { l = ChatService.shared.listenMessages(chatId: id) { messages = $0 } } }
        .onDisappear { l?.remove(); l = nil }
    }

    @ViewBuilder func bubble(_ m: ChatMessage) -> some View {
        let mine = m.senderId == session.uid
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if m.isAI { HStack(spacing: 4) { AIBadge(); Text(AppConstants.aiName).font(.caption2) } }
                if let u = m.imageURL, let url = URL(string: u) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxWidth: 200, maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !m.text.isEmpty {
                    Text(m.text).padding(10)
                        .background(mine ? Color.blue : (m.isAI ? Color.orange.opacity(0.3) : Color.gray.opacity(0.3)), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    func send(image: UIImage?) {
        guard let id = chat.id else { return }
        let t = image == nil ? text : ""
        sending = true; error = nil
        Task { defer { sending = false }
            do { try await ChatService.shared.send(chatId: id, text: t, image: image); if image == nil { text = "" } }
            catch { self.error = error.localizedDescription }
        }
    }
}
