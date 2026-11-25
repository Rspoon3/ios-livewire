import Foundation
import LWAPI
import LWFileSystem
import LWLogging
import LWStore

/// Build-time settings, read from the Info.plist of whichever target is running (app or widget).
///
/// The only one is the App Group identifier, which comes from the `LW_APP_GROUP` build setting.
/// Secrets are never build settings; they live in the Keychain.
public struct RuntimeConfiguration: Sendable {
    public var appGroupIdentifier: String?
    /// The disk. Debug-build tests pass an `InMemoryFileSystem`.
    public var fileSystem: any FileSystem

    public init(appGroupIdentifier: String?, fileSystem: any FileSystem = DiskFileSystem()) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileSystem = fileSystem
    }

    public init(bundle: Bundle = .main, fileSystem: any FileSystem = DiskFileSystem()) {
        func value(_ key: String) -> String? {
            guard let text = bundle.object(forInfoDictionaryKey: key) as? String,
                  !text.isEmpty,
                  !text.hasPrefix("$(")  // an unexpanded build variable
            else { return nil }
            return text
        }
        self.init(appGroupIdentifier: value("LWAppGroup"), fileSystem: fileSystem)
    }

    public var sharedContainer: URL? {
        appGroupIdentifier.flatMap { fileSystem.sharedContainer(appGroup: $0) }
    }

    /// Log locations for this process.
    public func logLocations() -> LogLocations {
        LogLocations(documents: fileSystem.documentsDirectory, sharedContainer: sharedContainer)
    }

    public func logExport() -> LogExport {
        LogExport(locations: logLocations(), fileSystem: fileSystem)
    }

    /// Where the snapshot lives: the App Group container if available, else Application Support
    /// (the widget then only sees stale data, and a warning is logged).
    public func snapshotDirectory() -> URL {
        (sharedContainer ?? fileSystem.applicationSupportDirectory)
            .appendingPathComponent("Snapshot", isDirectory: true)
    }

    public func snapshotStore() -> SnapshotStore {
        SnapshotStore(directory: snapshotDirectory(), fileSystem: fileSystem)
    }
}

/// Process-level setup. Call `bootstrap` first thing in the app and in the widget extension.
public enum LiveWireRuntime {
    @discardableResult
    public static func bootstrap(process: LogProcess, bundle: Bundle = .main) -> RuntimeConfiguration {
        let configuration = RuntimeConfiguration(bundle: bundle)
        let locations = configuration.logLocations()
        LWLogging.bootstrap(process: process, directory: locations.directory(for: process), fileSystem: configuration.fileSystem)

        let log = LWLogger("runtime")
        log.info("Process \(process.rawValue) starting. App Group: \(configuration.appGroupIdentifier ?? "none"), container available: \(configuration.sharedContainer != nil)")
        if configuration.sharedContainer == nil {
            log.warning("No App Group container. The widget cannot share data or sign-in with the app until the App Group entitlement is set up (check the App Groups capability and your signing team).")
        }
        return configuration
    }
}
