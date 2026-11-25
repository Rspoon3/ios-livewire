import LWLogging
import Observation

@MainActor
@Observable
final class SignInViewModel {
    var email = ""
    var password = ""
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?
    /// For the share-logs button: a sign-in failure is the first thing worth sharing.
    let logExport: LogExport

    @ObservationIgnored private let auth: any SigningIn

    init(auth: any SigningIn, logExport: LogExport) {
        self.auth = auth
        self.logExport = logExport
    }

    var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !isSigningIn }

    func submit() async {
        guard canSubmit else { return }
        isSigningIn = true
        errorMessage = nil
        defer {
            // The password is never kept longer than the request needs it.
            password = ""
            isSigningIn = false
        }
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
