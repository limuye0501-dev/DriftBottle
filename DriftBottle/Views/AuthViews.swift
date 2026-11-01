import SwiftUI
import AuthenticationServices

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    var body: some View {
        switch session.state {
        case .loading: ZStack { NightBeachBackground(); ProgressView("加载中…") }
        case .signedOut: LoginView()
        case .needsOnboarding: OnboardingView()
        case .ready: MainTabView()
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    var body: some View {
        ZStack {
            NightBeachBackground()
            VStack(spacing: 24) {
                Spacer()
                Text("漂流瓶").font(.system(size: 44, weight: .bold, design: .serif))
                Text("把心事装进瓶子，交给今晚的海").foregroundStyle(.secondary)
                Spacer()
                SignInWithAppleButton(.signIn, onRequest: session.prepare,
                                      onCompletion: { r in Task { await session.handle(r) } })
                    .signInWithAppleButtonStyle(.white).frame(height: 50).padding(.horizontal, 32)
                Text("仅支持通过 Apple 登录，我们不会收集你的手机号或真实姓名").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let e = session.error { Text(e).foregroundStyle(.red).font(.footnote) }
            }.padding(.bottom, 40)
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var session: SessionStore
    @State private var nickname = ""
    @State private var gender: Gender = .male
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -22, to: Date())!
    @State private var confirm = false
    private var maxDate: Date { Calendar.current.date(byAdding: .year, value: -18, to: Date())! }
    private var valid: Bool { (1...12).contains(nickname.trimmingCharacters(in: .whitespaces).count) && !SensitiveWordFilter.contains(nickname) }
    var body: some View {
        NavigationStack {
            Form {
                Section("昵称") { TextField("1–12 个字", text: $nickname) }
                Section { Picker("性别", selection: $gender) { ForEach(Gender.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                    header: { Text("性别") } footer: { Text("性别和生日注册后不可修改") }
                Section("生日") { DatePicker("生日", selection: $birthday, in: ...maxDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "zh_CN")) }
                Button("开始漂流") { confirm = true }.disabled(!valid)
                if let e = session.error { Text(e).foregroundStyle(.red) }
            }
            .navigationTitle("完善资料")
            .alert("确认信息", isPresented: $confirm) {
                Button("确认") { Task { await session.completeOnboarding(nickname: nickname, gender: gender, birthday: birthday) } }
                Button("再看看", role: .cancel) {}
            } message: { Text("性别：\(gender.title)\n生日确认后将无法修改") }
        }
    }
}
