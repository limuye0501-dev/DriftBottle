import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    var body: some View {
        switch session.state {
        case .loading, .failed: WelcomeView()
        case .needsOnboarding: OnboardingView()
        case .ready: MainTabView()
        }
    }
}

/// 启动页：自动匿名登录，无需注册
struct WelcomeView: View {
    @EnvironmentObject var session: SessionStore
    var body: some View {
        ZStack {
            NightBeachBackground()
            VStack(spacing: 24) {   // 在安全区内布局，避开刘海/灵动岛
                Spacer()
                Text("漂流瓶").font(.system(.largeTitle, design: .serif).weight(.bold)).scaleEffect(1.3).padding(.bottom, 8)
                Text("把心事装进瓶子，交给今晚的海").foregroundStyle(.secondary)
                Spacer()
                if session.state == .failed {
                    if let e = session.error { Text(e).foregroundStyle(.red).font(.footnote) }
                    Button("重试") { Task { await session.signInAnonymously() } }.buttonStyle(.borderedProminent)
                } else {
                    ProgressView("正在为你准备一片海…")
                }
                Text("无需注册，不收集手机号、姓名或邮箱").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var session: SessionStore
    @State private var gender: Gender?
    @State private var ageText = ""
    @State private var nickname = SessionStore.randomNickname()
    @State private var confirm = false
    @State private var saving = false
    private var age: Int? { Int(ageText) }
    private var ageValid: Bool { if let a = age { return (18...80).contains(a) }; return false }
    private var nameValid: Bool { (1...12).contains(nickname.trimmingCharacters(in: .whitespaces).count) && !SensitiveWordFilter.contains(nickname) }
    var body: some View {
        NavigationStack {
            Form {
                Section { Picker("性别", selection: $gender) {
                        Text("男").tag(Gender?.some(.male)); Text("女").tag(Gender?.some(.female)) }.pickerStyle(.segmented) }
                    header: { Text("性别") }
                Section {
                    TextField("请输入年龄", text: $ageText).keyboardType(.numberPad)
                        .onChange(of: ageText) { _, v in ageText = String(v.filter(\.isNumber).prefix(2)) }
                } header: { Text("年龄") } footer: {
                    if !ageText.isEmpty && !ageValid { Text("仅限 18 岁及以上使用").foregroundStyle(.red) }
                    else { Text("性别和年龄提交后不可修改；只会匹配异性、年龄相差 10 岁以内的旅人") }
                }
                Section { HStack { TextField("昵称", text: $nickname)
                        Button { nickname = SessionStore.randomNickname() } label: { Image(systemName: "dice") } } }
                    header: { Text("昵称（已随机生成，可修改）") }
                Button(saving ? "提交中…" : "开始漂流") { confirm = true }.disabled(gender == nil || !ageValid || !nameValid || saving)
                if let e = session.error { Text(e).foregroundStyle(.red) }
            }
            .navigationTitle("你好，陌生人")
            .alert("确认信息", isPresented: $confirm) {
                Button("确认") { guard let gender, let age else { return }
                    Task { saving = true; await session.completeOnboarding(gender: gender, age: age, nickname: nickname); saving = false } }
                Button("再看看", role: .cancel) {}
            } message: { Text("性别：\(gender?.title ?? "")　年龄：\(ageText)\n确认后将无法修改") }
        }
    }
}
