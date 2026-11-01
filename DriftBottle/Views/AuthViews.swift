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
                Text(L("app.name")).font(.system(.largeTitle, design: .serif).weight(.bold)).scaleEffect(1.3).padding(.bottom, 8)
                Text(L("welcome.tagline")).foregroundStyle(.secondary)
                Spacer()
                if session.state == .failed {
                    if let e = session.error { Text(e).foregroundStyle(.red).font(.footnote) }
                    Button(L("common.retry")) { Task { await session.signInAnonymously() } }.buttonStyle(.borderedProminent)
                } else {
                    ProgressView(L("loading.sea"))
                }
                Text(L("welcome.privacy")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                Section { Picker(L("onb.gender"), selection: $gender) {
                        Text(L("gender.male")).tag(Gender?.some(.male)); Text(L("gender.female")).tag(Gender?.some(.female)) }.pickerStyle(.segmented) }
                    header: { Text(L("onb.gender")) }
                Section {
                    TextField(L("onb.age_placeholder"), text: $ageText).keyboardType(.numberPad)
                        .onChange(of: ageText) { _, v in ageText = String(v.filter(\.isNumber).prefix(2)) }
                } header: { Text(L("onb.age")) } footer: {
                    if !ageText.isEmpty && !ageValid { Text(L("onb.age_min")).foregroundStyle(.red) }
                    else { Text(L("onb.locked")) }
                }
                Section { HStack { TextField(L("onb.nickname"), text: $nickname)
                        Button { nickname = SessionStore.randomNickname() } label: { Image(systemName: "dice") } } }
                    header: { Text(L("onb.nickname_header")) }
                Button(saving ? L("onb.submitting") : L("onb.start")) { confirm = true }.disabled(gender == nil || !ageValid || !nameValid || saving)
                if let e = session.error { Text(e).foregroundStyle(.red) }
            }
            .navigationTitle(L("onb.title"))
            .alert(L("onb.confirm_title"), isPresented: $confirm) {
                Button(L("common.confirm")) { guard let gender, let age else { return }
                    Task { saving = true; await session.completeOnboarding(gender: gender, age: age, nickname: nickname); saving = false } }
                Button(L("onb.review"), role: .cancel) {}
            } message: { Text(L("onb.confirm_msg", gender?.title ?? "", ageText)) }
        }
    }
}
