import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(model: AppModel) {
        _viewModel = State(initialValue: SettingsViewModel(app: model))
    }

    var body: some View {
        Form {
            Section("Logs") {
                LabeledContent("Log files", value: "\(viewModel.logFileCount)")
                LogShareButton(export: viewModel.logExport)
                Button("Delete all logs", systemImage: "trash", role: .destructive) { viewModel.isConfirmingClear = true }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Logs include every API response so the API can be mapped. They contain your bike location and rides, but never your password or tokens, and the VIN is masked. Check them before posting anything publicly.\n\nShare logs also works from the sign-in screen. They are also in the Files app under On My iPhone → this app → Logs.")
            }

            Section("Account") {
                Button("Sign out", role: .destructive) { Task { await viewModel.signOut() } }
            }

            Section("About") {
                Text("Unofficial. Not affiliated with LiveWire or Harley-Davidson. It uses an undocumented API that can change or stop working at any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear { viewModel.refreshLogCount() }
        .confirmationDialog("Delete all log files?", isPresented: $viewModel.isConfirmingClear, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { viewModel.clearLogs() }
        }
    }
}
