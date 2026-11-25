import Foundation
import LWLogging
import LWModels
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
        var request = URLRequest(url: configuration.gigyaURL.appendingPathComponent("accounts.login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.identity.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Self.formEncoded([
            ("apiKey", configuration.gigyaAPIKey),
            ("loginID", email),
            ("password", password),
            ("include", "profile,data"),
            ("format", "json"),
        ])

        // The response includes profile data and session secrets, so only the outcome is logged.
        let response = try await wire.perform(request, label: "POST gigya accounts.login", logBodies: false)
        let errorCode = response.body["errorCode"]?.intValue ?? 0
        if errorCode != 0 {
            let message = response.body["errorMessage"]?.textValue ?? "error \(errorCode)"
            log.warning("Gigya login failed: errorCode=\(errorCode) message=\(message)")
            if Self.credentialErrors.contains(errorCode) {
                throw LiveWireAPIError.invalidCredentials("Wrong email or password, or the account setup is unfinished (\(errorCode)).")
            }
            throw LiveWireAPIError.gigya(code: errorCode, message: message)
        }
        guard let uid = response.body["UID"]?.textValue else {
            throw LiveWireAPIError.unexpectedResponse("Gigya login returned no UID")
        }
        log.info("Gigya login succeeded (UID received)")
        return uid
    }

    private func mintToken(uid: String) async throws -> String {
        let deviceUUID = try deviceUUID()
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent("session"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "brand", value: configuration.brand)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        for (name, value) in configuration.identity.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONEncoder().encode([
            "UID": uid,
            "deviceUUID": deviceUUID,
            "dataCenter": configuration.dataCenter,
        ])

        let response = try await wire.perform(request, label: "POST session?brand=\(configuration.brand)")
        guard let jwt = response.body["jwt"]?.textValue else {
            let detail = response.body.path("error", "description")?.textValue ?? "HTTP \(response.status)"
            throw LiveWireAPIError.sessionFailed(detail)
        }
        do { try secrets.set(jwt, for: .sessionToken) } catch { throw LiveWireAPIError.secureStorage("\(error)") }
        cachedToken = jwt
        if let accepted = response.body["termsAccepted"]?.boolValue {
            log.info("Session token stored (termsAccepted: \(accepted))")
        }
        return jwt
    }

    /// Gigya expects `application/x-www-form-urlencoded`. `+` and `&` in passwords must be escaped,
    /// which `URLComponents` does not do for query-style bodies.
    static func formEncoded(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = pairs
            .map { name, value in
                let encodedName = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedName)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}
