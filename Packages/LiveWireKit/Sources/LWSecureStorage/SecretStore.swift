import Foundation
import LWLogging
import Valet

/// Everything this app treats as secret. Nothing else is stored in the Keychain, and nothing in
/// this list is ever written anywhere but the Keychain.
public enum SecretKey: String, CaseIterable, Sendable {
    /// Gigya account UID. py-livewire documents that the session token can be minted from the UID
    /// alone, so the password is never stored.
    case gigyaUID
    /// The LiveWire session JWT.
    case sessionToken
    /// The identifier this install uses with the backend. Pairing with a bike is tied to it.
    case deviceUUID
}

public protocol SecretStore: Sendable {
    func string(for key: SecretKey) throws -> String?
    func set(_ value: String, for key: SecretKey) throws
    func remove(_ key: SecretKey) throws
}

public struct SecretStoreError: Error, CustomStringConvertible, Equatable {
    public let underlying: String
    public var description: String { "Keychain error: \(underlying)" }
}

/// Keychain-backed store, built on [Valet](https://github.com/square/Valet).
///
/// Items use `afterFirstUnlockThisDeviceOnly`: the widget can read them while the phone is locked
/// (once it has been unlocked since boot), and they never leave the device through a backup.
///
/// The app and the widget share items through the App Group. On iOS an App Group identifier is also
/// a valid keychain access group, so both targets only need the same `com.apple.security.application-groups`
/// entitlement. If the group is unavailable (for example an unsigned simulator build), the store
/// falls back to a private, per-process Valet and logs a warning.
public struct KeychainSecretStore: SecretStore {
    private let valet: Valet
    private let log = LWLogger("keychain")

    /// - Parameter appGroupIdentifier: e.g. `group.dev.example.ios-livewire`, or `nil` for a private store.
    public init(appGroupIdentifier: String? = nil) {
        let log = LWLogger("keychain")
        if let appGroupIdentifier,
           let prefixEnd = appGroupIdentifier.firstIndex(of: "."),
           let shared = SharedGroupIdentifier(
               groupPrefix: String(appGroupIdentifier[..<prefixEnd]),
               nonEmptyGroup: String(appGroupIdentifier[appGroupIdentifier.index(after: prefixEnd)...])
           ) {
            let candidate = Valet.sharedGroupValet(with: shared, accessibility: .afterFirstUnlockThisDeviceOnly)
            if candidate.canAccessKeychain() {
                valet = candidate
                return
            }
            log.warning("App Group keychain is not accessible; using a private keychain. The widget will not see the sign-in.")
        }
        // `Identifier(nonEmpty:)` only returns nil for an empty string.
        valet = Valet.valet(
            with: Identifier(nonEmpty: "ios-livewire")!,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    public func string(for key: SecretKey) throws -> String? {
        do {
            return try valet.string(forKey: key.rawValue)
        } catch KeychainError.itemNotFound {
            return nil
        } catch {
            log.error("read \(key.rawValue) failed: \(error)")
            throw SecretStoreError(underlying: "\(error)")
        }
    }

    public func set(_ value: String, for key: SecretKey) throws {
        do {
            try valet.setString(value, forKey: key.rawValue)
        } catch {
            log.error("write \(key.rawValue) failed: \(error)")
            throw SecretStoreError(underlying: "\(error)")
        }
    }

    public func remove(_ key: SecretKey) throws {
        do {
            try valet.removeObject(forKey: key.rawValue)
        } catch KeychainError.itemNotFound {
            return
        } catch {
            log.error("delete \(key.rawValue) failed: \(error)")
            throw SecretStoreError(underlying: "\(error)")
        }
    }
}

/// For tests and previews. Never use it for real credentials.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretKey: String]

    public init(_ values: [SecretKey: String] = [:]) {
        self.values = values
    }

    public func string(for key: SecretKey) throws -> String? {
        lock.withLock { values[key] }
    }

    public func set(_ value: String, for key: SecretKey) throws {
        lock.withLock { values[key] = value }
    }

    public func remove(_ key: SecretKey) throws {
        lock.withLock { _ = values.removeValue(forKey: key) }
    }
}
