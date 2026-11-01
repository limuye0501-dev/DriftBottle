import SwiftUI

/// 信纸背景：带横线与轻微纸纹；年卡专属样式只改变纸色/点缀
struct LetterPaper: View {
    var style: BottleStyle = .classic
    static func tint(_ s: BottleStyle) -> Color {
        switch s {
        case .classic: Theme.paper
        case .moonlight: Color(hex: 0xE4E8F4)
        case .amber: Color(hex: 0xF6DFB2)
        case .sakura: Color(hex: 0xF6E1E4)
        }
    }
    /// v4：撕边羊皮纸纹理 × 信纸颜色（正片叠底），横线 + 角落刻印（SF Symbol，非 emoji）
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("Parchment").resizable().colorMultiply(Self.tint(style))
                .shadow(color: .black.opacity(0.7), radius: 12, y: 14)
            RuledLines(spacing: 34).padding(.horizontal, 30).padding(.top, 44).padding(.bottom, 36)
            if let sym = style == .sakura ? "camera.macro" : (style == .moonlight ? "moon" : nil) {
                Image(systemName: sym).font(.title3).foregroundStyle(Theme.ink.opacity(0.22)).padding(30)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 捡到的信：先展开信纸，再选择「扔回海里」或「回信给 TA」（回信前会先保留）
struct LetterView: View {
    let bottle: Bottle
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var unfolded = false
    @State private var kept = false
    @State private var reply = ""
    @State private var error: String?
    @State private var reportSheet = false
    @State private var working = false
    @FocusState private var replyFocused: Bool

    private var style: BottleStyle { BottleStyle(rawValue: bottle.style ?? "classic") ?? .classic }
    private var driftText: String {
        let days = max(0, Calendar.current.dateComponents([.day], from: bottle.createdAt, to: .now).day ?? 0)
        return days == 0 ? L("letter.just_now") : L("letter.days", days)
    }
    private var age: Int { Calendar.current.component(.year, from: .now) - bottle.senderBirthYear }

    var body: some View {
        ZStack {
            BoardwalkBackground().overlay(Color.black.opacity(0.5).ignoresSafeArea())
            VStack(spacing: 14) {
                HStack {
                    Text(driftText).font(Theme.body(.caption).weight(.semibold)).engraved()
                    Spacer()
                    Menu {
                        Button(L("common.report")) { reportSheet = true }
                        Button(L("common.block"), role: .destructive) { act { try await UserService.shared.block(bottle.senderId); try? await BottleService.shared.release(bottle.id!) } }
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.bold)).stamped()
                            .frame(width: 38, height: 38).background(Circle().fill(Theme.brassGradient).shadow(color: .black.opacity(0.6), radius: 4, y: 3))
                    }
                    .accessibilityLabel(L("a11y.more"))
                }
                ScrollView { letter.padding(.vertical, 6) }
                    .scrollIndicators(.hidden)
                if let error { Text(error).font(Theme.body(.footnote)).foregroundStyle(.red) }
                actions
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        }
        .foregroundStyle(Theme.paper)
        .onAppear {
            SoundFX.shared.play(.paper, volume: 0.7)
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8)) { unfolded = true }
        }
        .confirmationDialog(L("report.title"), isPresented: $reportSheet) {
            ForEach(ReportReason.all, id: \.self) { r in
                Button(L(r)) { act { try await UserService.shared.report(targetUserId: bottle.senderId, bottleId: bottle.id, reason: r); try? await BottleService.shared.release(bottle.id!) } }
            }
        }
        .interactiveDismissDisabled()   // 必须选择扔回或回信
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("\(bottle.senderGender == .female ? "♀" : "♂") " + L("letter.age", age), systemImage: "person.fill")
                    .labelStyle(.titleOnly).font(Theme.body(.caption)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.ink.opacity(0.08), in: Capsule())
                Text(L("letter.written_at", bottle.createdAt.formatted(.dateTime.hour().minute()))).font(Theme.body(.caption))
                Spacer()
                Text(L("letter.repliers", bottle.replierIds.count, AppConstants.maxRepliers)).font(Theme.body(.caption2))
            }
            .foregroundStyle(Theme.ink.opacity(0.6))
            Text(bottle.text).font(Theme.letter(.title3)).foregroundStyle(Theme.ink).lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let u = bottle.visibleImageURL, let url = URL(string: u) {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(alignment: .bottom) {
                WaxSeal(size: 48).rotationEffect(.degrees(-8))
                Spacer()
                Text("—— \(bottle.senderNickname)").font(Theme.letter(.footnote)).foregroundStyle(Theme.ink.opacity(0.55))
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 40)
        .background(LetterPaper(style: style))
        .rotationEffect(.degrees(unfolded ? -1.2 : -6))
        .scaleEffect(unfolded ? 1 : 0.86, anchor: .bottom)
        .opacity(unfolded ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actions: some View {
        if kept {
            VStack(spacing: 10) {
                TextField(L("letter.reply_placeholder"), text: $reply, axis: .vertical)
                    .font(Theme.letter(.body)).lineLimit(2...6).focused($replyFocused)
                    .foregroundStyle(Theme.parchInk).padding(14)
                    .background(Color(hex: 0xF1E4C4), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: 0x785028).opacity(0.5)))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                Button(working ? L("letter.sending") : L("letter.send")) {
                    act { _ = try await BottleService.shared.reply(bottle.id!, text: reply); Feel.sent() }
                }
                .buttonStyle(BrassButtonStyle()).disabled(working || reply.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button(L("letter.throw_back")) { Feel.tap(); act { try await BottleService.shared.release(bottle.id!) } }
                    .buttonStyle(WoodButtonStyle())
                Button(L("letter.reply")) {
                    Feel.tap()
                    Task { working = true; defer { working = false }
                        do { try await BottleService.shared.keep(bottle.id!); withAnimation(reduceMotion ? nil : .snappy) { kept = true }; replyFocused = true }
                        catch { self.error = error.localizedDescription; Feel.warning() } }
                }
                .buttonStyle(BrassButtonStyle(minHeight: 56))
                .layoutPriority(1)
            }
            .disabled(working)
            Text(L("letter.footer", AppConstants.maxRepliers))
                .font(Theme.body(.caption2)).engraved().opacity(0.85).multilineTextAlignment(.center)
        }
    }

    func act(_ f: @escaping () async throws -> Void) {
        Task { working = true; defer { working = false }
            do { try await f(); dismiss() } catch { self.error = error.localizedDescription; Feel.warning() } }
    }
}
