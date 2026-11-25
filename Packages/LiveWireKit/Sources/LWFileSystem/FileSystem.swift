import Foundation

/// How a file is protected when it is written. Maps to iOS data protection.
public enum FileProtection: Sendable {
    /// The system default.
    case standard
    /// Readable from the first unlock after a restart on, so a widget can use it while the phone is
    /// locked.
    case untilFirstUserAuthentication
}

/// The disk, as the rest of the package sees it.
///
/// Code that reads or writes files takes a `FileSystem` instead of calling `FileManager.default`, so
/// tests can run against `InMemoryFileSystem`, and make a read or a write fail, without touching the
/// real disk.
public protocol FileSystem: Sendable {
    var temporaryDirectory: URL { get }
    var documentsDirectory: URL { get }
    var applicationSupportDirectory: URL { get }

    /// The App Group's shared container, or `nil` when the entitlement is missing.
    func sharedContainer(appGroup identifier: String) -> URL?

    /// Creates the directory and any missing parents. Does nothing if it already exists.
    func createDirectory(at url: URL) throws
    /// The files and directories directly inside `url`.
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func read(_ url: URL) throws -> Data
    /// Writes atomically, so a reader never sees a half-written file.
    func write(_ data: Data, to url: URL, protection: FileProtection) throws
    func remove(_ url: URL) throws
    func copy(from source: URL, to destination: URL) throws
    func modificationDate(of url: URL) -> Date?
}

extension FileSystem {
    public func write(_ data: Data, to url: URL) throws {
        try write(data, to: url, protection: .standard)
    }

    public func readString(_ url: URL) throws -> String {
        String(decoding: try read(url), as: UTF8.self)
    }
}
