import Foundation

// The small slices of `AppModel` that the view models need. A view model asks for the slice it uses,
// so a test can hand it a fake and no screen ever sees the API, the Keychain or the whole app model.

@MainActor
protocol SigningIn: AnyObject {
    /// Throws with a message fit to show when sign-in fails.
    func signIn(email: String, password: String) async throws
}

@MainActor
protocol BikePairing: AnyObject {
    func requestPairingCode(bikeID: String) async throws
    func verifyPairingCode(bikeID: String, code: String) async throws
    /// Waits for the backend to confirm the pairing. `false` if it did not in time.
    func finishPairing(bikeID: String) async throws -> Bool
}

/// A label and a value, for the detail lists.
struct DetailRow: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let value: String
}
