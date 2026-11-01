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
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.tint(style)))
            // 纸边轻微暗角
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [.clear, Color(hex: 0x8A6A3A).opacity(0.18)]),
                     center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: min(size.width, size.height) * 0.35, endRadius: max(size.width, size.height) * 0.75))
            var y: CGFloat = 64
            while y < size.height - 20 {
                ctx.fill(Path(CGRect(x: 18, y: y, width: size.width - 36, height: 0.6)), with: .color(Theme.ink.opacity(0.14)))
                y += 34
            }
            if style == .sakura || style == .moonlight {
                let sym = style == .sakura ? "✿" : "☾"
                ctx.draw(Text(sym).font(.system(size: 22)).foregroundColor(Theme.ink.opacity(0.18)), at: CGPoint(x: size.width - 30, y: 30))
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
        return days == 0 ? "今晚刚刚漂来" : "漂了 \(days) 天"
    }
    private var age: Int { Calendar.current.component(.year, from: .now) - bottle.senderBirthYear }

    var body: some View {
        ZStack {
            NightBeachBackground(showLighthouse: false).overlay(Theme.night.opacity(0.55).ignoresSafeArea())
            VStack(spacing: 14) {
                HStack {
                    Text(driftText).font(Theme.body(.caption)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Menu {
                        Button("举报") { reportSheet = true }
                        Button("拉黑", role: .destructive) { act { try await UserService.shared.block(bottle.senderId); try? await BottleService.shared.release(bottle.id!) } }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.secondary).padding(6) }
                    .accessibilityLabel("更多")
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
        .confirmationDialog("举报原因", isPresented: $reportSheet) {
            ForEach(ReportReason.all, id: \.self) { r in
                Button(r) { act { try await UserService.shared.report(targetUserId: bottle.senderId, bottleId: bottle.id, reason: r); try? await BottleService.shared.release(bottle.id!) } }
            }
        }
        .interactiveDismissDisabled()   // 必须选择扔回或回信
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("\(bottle.senderGender == .female ? "♀" : "♂") \(age) 岁", systemImage: "person.fill")
                    .labelStyle(.titleOnly).font(Theme.body(.caption)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.ink.opacity(0.08), in: Capsule())
                Text("\(bottle.createdAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))) 写下").font(Theme.body(.caption))
                Spacer()
                Text("\(bottle.replierIds.count)/\(AppConstants.maxRepliers) 人回信").font(Theme.body(.caption2))
            }
            .foregroundStyle(Theme.ink.opacity(0.6))
            Text(bottle.text).font(Theme.letter(.title3)).foregroundStyle(Theme.ink).lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let u = bottle.imageURL, let url = URL(string: u) {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(alignment: .bottom) {
                Text("漂").font(.system(.footnote, design: .serif).weight(.bold)).foregroundStyle(Theme.paper)
                    .frame(width: 40, height: 40).background(Circle().fill(Color(hex: 0xA8322D)))
                    .accessibilityHidden(true)
                Spacer()
                Text("—— \(bottle.senderNickname)").font(Theme.letter(.footnote)).foregroundStyle(Theme.ink.opacity(0.55))
            }
        }
        .padding(22)
        .background(LetterPaper(style: style))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .rotationEffect(.degrees(unfolded ? -1.2 : -6))
        .scaleEffect(unfolded ? 1 : 0.86, anchor: .bottom)
        .opacity(unfolded ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actions: some View {
        if kept {
            VStack(spacing: 10) {
                TextField("写下你的回信（免费）…", text: $reply, axis: .vertical)
                    .font(Theme.letter(.body)).lineLimit(2...6).focused($replyFocused)
                    .padding(14).glass(18)
                Button(working ? "寄出中…" : "寄出回信") {
                    act { _ = try await BottleService.shared.reply(bottle.id!, text: reply); Feel.sent() }
                }
                .buttonStyle(AmberButtonStyle()).disabled(working || reply.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button("扔回海里") { Feel.tap(); act { try await BottleService.shared.release(bottle.id!) } }
                    .buttonStyle(GlassButtonStyle())
                Button("回信给 TA") {
                    Feel.tap()
                    Task { working = true; defer { working = false }
                        do { try await BottleService.shared.keep(bottle.id!); withAnimation(reduceMotion ? nil : .snappy) { kept = true }; replyFocused = true }
                        catch { self.error = error.localizedDescription; Feel.warning() } }
                }
                .buttonStyle(AmberButtonStyle())
                .layoutPriority(1)
            }
            .disabled(working)
            Text("扔回去，它会继续漂向下一个人 · 每个瓶子最多 \(AppConstants.maxRepliers) 人回信")
                .font(Theme.body(.caption2)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
        }
    }

    func act(_ f: @escaping () async throws -> Void) {
        Task { working = true; defer { working = false }
            do { try await f(); dismiss() } catch { self.error = error.localizedDescription; Feel.warning() } }
    }
}
