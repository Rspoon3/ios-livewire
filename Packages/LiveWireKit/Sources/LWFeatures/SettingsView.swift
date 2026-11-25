import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var confirmClear = false
    @State private var logCount = 0

    var body: some View {
        Form {
            Section("Logs") {
                LabeledContent("Log files", value: "\(logCount)")
                LogShareButton(model: model)
                Button("Delete all logs", systemImage: "trash", role: .destructive) { confirmClear = true }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Logs include every API response so the API can be mapped. They contain your VIN, bike location and rides, but never your password or tokens. Check them before posting anything publicly.\n\nShare logs also works from the setup and sign-in screens. They are also in the Files app under On My iPhone → this app → Logs.")
            }

            Section("Account") {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            }

            Section("About") {
                Text("Unofficial. Not affiliated with LiveWire or Harley-Davidson. It uses an undocumented API that can change or stop working at any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear { logCount = model.logFileCount }
        .confirmationDialog("Delete all log files?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.clearLogs()
                logCount = model.logFileCount
            }
        }
    }
}
