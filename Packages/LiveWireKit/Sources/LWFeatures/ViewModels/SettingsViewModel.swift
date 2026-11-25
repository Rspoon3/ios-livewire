import LWLogging
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var logFileCount = 0
    var isConfirmingClear = false
    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        logFileCount = app.logFileCount
    }

    var logExport: LogExport { app.logExport }

    func refreshLogCount() { logFileCount = app.logFileCount }

    func clearLogs() {
        app.clearLogs()
        refreshLogCount()
    }

    func signOut() async { await app.signOut() }
}
