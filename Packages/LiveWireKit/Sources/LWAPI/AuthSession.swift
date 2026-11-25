import Foundation
import LWLogging
import LWSecureStorage

/// Owns the sign-in state: Gigya UID, device UUID and session token, all in the Keychain.
///
/// Flow (from py-livewire, matching the iOS app's config):
/// 1. `accounts.login` at Gigya with email and password returns a `UID`. The password is used once
///    and never stored.
/// 2. `POST /session` with `{UID, deviceUUID, dataCenter}` returns a JWT.
/// 3. The JWT is sent as `Authorization: Bearer …` on every call. When the backend answers 401, a new
///    JWT is minted from the stored UID, with no password needed.
actor AuthSession {
    private let configuration: APIConfiguration
    private let secrets: any SecretStore
    private let wire: Wire
    private let log = LWLogger("auth")
    private var cachedToken: String?

    /// Gigya `errorCode`s that mean the credentials are the problem (per py-livewire).
    private static let credentialErrors: Set<Int> = [403_042, 206_001, 206_002]

    init(configuration: APIConfiguration, secrets: any SecretStore, wire: Wire) {
        self.configuration = configuration
        self.secrets = secrets
        self.wire = wire
    }

    // MARK: State

    func hasCredentials() -> Bool {
        (try? secrets.string(for: .gigyaUID)) != nil
    }

    /// The identifier this install registers with the backend. The app makes its own, once, and keeps
    /// it in the Keychain.
    ///
    /// It is lowercase, like the Android app's and py-livewire's. Early builds stored an uppercase
    /// one. That UUID was never paired, and its pairing request was never answered by the bike, so it
    /// is replaced by a fresh lowercase one.
    func deviceUUID() throws -> String {
        do {
            if let existing = try secrets.string(for: .deviceUUID) {
                if existing == existing.lowercased() { return existing }
                let replacement = UUID().uuidString.lowercased()
                try secrets.set(replacement, for: .deviceUUID)
                log.info("Replaced the uppercase device UUID \(existing) with \(replacement)")
                return replacement
            }
            let created = UUID().uuidString.lowercased()
            try secrets.set(created, for: .deviceUUID)
            log.info("Created a new device UUID \(created)")
            return created
        } catch let error as LiveWireAPIError {
            throw error
        } catch {
            throw LiveWireAPIError.secureStorage("\(error)")
        }
    }

    // MARK: Sign in / out

    func signIn(email: String, password: String) async throws {
        let uid = try await gigyaLogin(email: email, password: password)
        do { try secrets.set(uid, for: .gigyaUID) } catch { throw LiveWireAPIError.secureStorage("\(error)") }
        cachedToken = nil
        _ = try await mintToken(uid: uid)
    }

    func signOut() throws {
        cachedToken = nil
        // The device UUID is kept on purpose: pairing is tied to it, so signing back in does not
        // force a new pairing at the bike.
        try? secrets.remove(.gigyaUID)
        try? secrets.remove(.sessionToken)
        log.info("Signed out; UID and session token removed from the Keychain")
    }

    // MARK: Tokens

    func token() async throws -> String {
        if let cachedToken { return cachedToken }
        if let stored = try? secrets.string(for: .sessionToken) {
            cachedToken = stored
            return stored
        }
        return try await renew()
    }

    /// Mints a new token after the backend rejected `rejected`. If another caller (the widget, say)
    /// already replaced it, that newer token is used instead of minting yet another.
    func renew(rejected: String? = nil) async throws -> String {
        if let rejected, let stored = try? secrets.string(for: .sessionToken), stored != rejected {
            cachedToken = stored
            return stored
        }
        guard let uid = try? secrets.string(for: .gigyaUID) else { throw LiveWireAPIError.notSignedIn }
        return try await mintToken(uid: uid)
    }

    // MARK: Network

    private func gigyaLogin(email: String, password: String) async throws -> String {
        let login = GigyaLogin(apiKey: configuration.gigyaAPIKey, email: email, password: password)
        let response = try await wire.send(login, using: configuration).decode(GigyaLoginResponse.self)

        let errorCode = response.errorCode ?? 0
        if errorCode != 0 {
            let message = response.errorMessage ?? "error \(errorCode)"
            log.warning("Gigya login failed: errorCode=\(errorCode) message=\(message)")
            if Self.credentialErrors.contains(errorCode) {
                throw LiveWireAPIError.invalidCredentials("Wrong email or password, or the account setup is unfinished (\(errorCode)).")
            }
            throw LiveWireAPIError.gigya(code: errorCode, message: message)
        }
        guard let uid = response.uid, !uid.isEmpty else {
            throw LiveWireAPIError.unexpectedResponse("Gigya login returned no UID")
        }
        log.info("Gigya login succeeded (UID received)")
        return uid
    }

    private func mintToken(uid: String) async throws -> String {
        let request = SessionRequest(uid: uid, deviceUUID: try deviceUUID(), dataCenter: configuration.dataCenter)
        let response = try await wire.send(CreateSession(request: request), using: configuration)

        let session = try? response.decode(SessionResponse.self)
        guard let jwt = session?.jwt, !jwt.isEmpty else {
            let envelope = try? response.decode(ErrorEnvelope.self)
            throw LiveWireAPIError.sessionFailed(envelope?.error?.description ?? "HTTP \(response.status)")
        }
        do { try secrets.set(jwt, for: .sessionToken) } catch { throw LiveWireAPIError.secureStorage("\(error)") }
        cachedToken = jwt
        if let accepted = session?.termsAccepted {
            log.info("Session token stored (termsAccepted: \(accepted))")
        }
        return jwt
    }
}
