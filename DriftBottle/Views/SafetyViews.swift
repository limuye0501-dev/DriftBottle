import SwiftUI

/// 举报：选原因、说明 24 小时处理，并给出支持邮箱。
struct ReportSheet: View {
    let authorUid: String
    var bottleId: String?
    var messageId: String?
    var chatId: String?
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L("report.reviewed")).font(.footnote).foregroundStyle(.secondary)
                }
                Section(L("report.title")) {
                    ForEach(ReportReason.all, id: \.self) { reason in
                        Button(L(reason)) { submit(reason) }.disabled(sending || authorUid.isEmpty)
                    }
                }
                Section(L("report.email_label")) {
                    LabeledContent(L("report.email_label"), value: AppLinks.supportEmail)
                    Link(L("report.problem"), destination: AppLinks.reportProblem)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(L("letter.report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit(_ reason: String) {
        sending = true
        error = nil
        Task {
            do {
                try await UserService.shared.report(authorUid: authorUid, bottleId: bottleId, messageId: messageId, chatId: chatId, reason: reason)
                onDone()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                sending = false
            }
        }
    }
}

struct BannedView: View {
    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(L("banned.title")).font(.title2.weight(.semibold))
                Text(L("banned.body"))
                LabeledContent(L("settings.email"), value: AppLinks.supportEmail)
                Link(L("settings.report_problem"), destination: AppLinks.reportProblem)
            }
            .padding(24)
            .foregroundStyle(Theme.paper)
        }
    }
}
