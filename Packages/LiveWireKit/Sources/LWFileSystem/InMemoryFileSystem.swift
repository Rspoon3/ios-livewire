import Foundation

#if DEBUG

/// A file system that lives in memory, for tests. Debug builds only, so it never ships.
///
/// It behaves like the disk where the code under test can tell: a missing file throws on read, a
/// missing directory throws on listing, a write needs no parent directory but creates one, and every
/// write stamps the file with `now()`. `failNext` makes the next matching call throw.
public final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    public enum Operation: Sendable, Hashable {
        case read, write, remove, copy, createDirectory, contentsOfDirectory
    }

    private struct File {
        var data: Data
        var modified: Date
    }

    private let lock = NSLock()
    private var files: [String: File] = [:]
    private var directories: Set<String> = []
    private var failures: [Operation: Error] = [:]
    private var groups: [String: URL]
    private let now: @Sendable () -> Date

    public let temporaryDirectory = URL(filePath: "/memory/tmp", directoryHint: .isDirectory)
    public let documentsDirectory = URL(filePath: "/memory/Documents", directoryHint: .isDirectory)
    public let applicationSupportDirectory = URL(filePath: "/memory/Library/Application Support", directoryHint: .isDirectory)

    /// - Parameter appGroups: the App Group containers that exist. Any other group gets `nil`, as on a
    ///   build without the entitlement.
    public init(appGroups: [String: URL] = [:], now: @escaping @Sendable () -> Date = { Date() }) {
        self.groups = appGroups
        self.now = now
    }

    // MARK: Test helpers

    /// Makes the next call of `operation` throw `error`, once.
    public func failNext(_ operation: Operation, with error: Error = CocoaError(.fileWriteUnknown)) {
        lock.withLock { failures[operation] = error }
    }

    public func setModificationDate(_ date: Date, of url: URL) {
        lock.withLock { files[url.path]?.modified = date }
    }

    public func fileExists(at url: URL) -> Bool {
        lock.withLock { files[url.path] != nil || directories.contains(url.path) }
    }

    /// Every file path, sorted.
    public var allFilePaths: [String] { lock.withLock { files.keys.sorted() } }

    // MARK: FileSystem

    public func sharedContainer(appGroup identifier: String) -> URL? {
        lock.withLock { groups[identifier] }
    }

    public func createDirectory(at url: URL) throws {
        try lock.withLock {
            try failIfNeeded(.createDirectory)
            addDirectory(url.path)
        }
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try lock.withLock {
            try failIfNeeded(.contentsOfDirectory)
            let path = url.path
            guard directories.contains(path) else { throw CocoaError(.fileReadNoSuchFile) }
            let prefix = path.hasSuffix("/") ? path : path + "/"
            let children = Set(files.keys).union(directories)
                .filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") && $0 != path }
            return children.sorted().map { URL(filePath: $0) }
        }
    }

    public func read(_ url: URL) throws -> Data {
        try lock.withLock {
            try failIfNeeded(.read)
            guard let file = files[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
            return file.data
        }
    }

    public func write(_ data: Data, to url: URL, protection: FileProtection) throws {
        try lock.withLock {
            try failIfNeeded(.write)
            addDirectory(url.deletingLastPathComponent().path)
            files[url.path] = File(data: data, modified: now())
        }
    }

    public func remove(_ url: URL) throws {
        try lock.withLock {
            try failIfNeeded(.remove)
            let path = url.path
            if files.removeValue(forKey: path) != nil { return }
            guard directories.contains(path) else { throw CocoaError(.fileNoSuchFile) }
            let prefix = path + "/"
            files = files.filter { !$0.key.hasPrefix(prefix) }
            directories = directories.filter { $0 != path && !$0.hasPrefix(prefix) }
        }
    }

    public func copy(from source: URL, to destination: URL) throws {
        try lock.withLock {
            try failIfNeeded(.copy)
            guard let file = files[source.path] else { throw CocoaError(.fileReadNoSuchFile) }
            guard files[destination.path] == nil else { throw CocoaError(.fileWriteFileExists) }
            addDirectory(destination.deletingLastPathComponent().path)
            files[destination.path] = File(data: file.data, modified: now())
        }
    }

    public func modificationDate(of url: URL) -> Date? {
        lock.withLock { files[url.path]?.modified }
    }

    // MARK: Private

    private func failIfNeeded(_ operation: Operation) throws {
        if let error = failures.removeValue(forKey: operation) { throw error }
    }

    /// Adds a directory and all of its parents.
    private func addDirectory(_ path: String) {
        var current = path
        while current != "/", !current.isEmpty {
            directories.insert(current)
            current = (current as NSString).deletingLastPathComponent
        }
    }
}

#endif
