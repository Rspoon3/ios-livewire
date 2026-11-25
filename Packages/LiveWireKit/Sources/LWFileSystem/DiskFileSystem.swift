import Foundation

/// The real disk, through `FileManager`.
public struct DiskFileSystem: FileSystem {
    public init() {}

    public var temporaryDirectory: URL { FileManager.default.temporaryDirectory }

    public var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? temporaryDirectory
    }

    public var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? temporaryDirectory
    }

    public func sharedContainer(appGroup identifier: String) -> URL? {
        guard !identifier.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL, protection: FileProtection) throws {
        var options: Data.WritingOptions = [.atomic]
        if protection == .untilFirstUserAuthentication { options.insert(.completeFileProtectionUntilFirstUserAuthentication) }
        try data.write(to: url, options: options)
    }

    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func copy(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
