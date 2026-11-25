import Foundation
import LWFileSystem

/// Where log files live.
///
/// - `appLogs`: written by the app. Lives in `Documents/Logs/app`, which the app exposes through
///   Files and Finder file sharing (`UIFileSharingEnabled`).
/// - `widgetLogs`: written by the widget extension, inside the shared App Group container (the
///   extension cannot write to the app's Documents folder).
/// - `mirroredWidgetLogs`: the app copies the widget's files here so they show up next to its own.
public struct LogLocations: Sendable {
    public var appLogs: URL
    public var widgetLogs: URL
    public var mirroredWidgetLogs: URL

    /// - Parameters:
    ///   - documents: the app's Documents directory.
    ///   - sharedContainer: the App Group container, or `nil` when the entitlement is missing
    ///     (the widget then falls back to its own Application Support directory).
    public init(documents: URL, sharedContainer: URL?) {
        let logsRoot = documents.appendingPathComponent("Logs", isDirectory: true)
        appLogs = logsRoot.appendingPathComponent("app", isDirectory: true)
        mirroredWidgetLogs = logsRoot.appendingPathComponent("widget", isDirectory: true)
        widgetLogs = (sharedContainer ?? documents)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("widget", isDirectory: true)
    }

    public func directory(for process: LogProcess) -> URL {
        switch process {
        case .app: appLogs
        case .widget: widgetLogs
        }
    }
}

/// Reads, merges and clears the log files, through a `FileSystem`.
public struct LogExport: Sendable {
    public let locations: LogLocations
    private let fileSystem: any FileSystem

    public init(locations: LogLocations, fileSystem: any FileSystem = DiskFileSystem()) {
        self.locations = locations
        self.fileSystem = fileSystem
    }

    /// Copies the widget's log files next to the app's, so one folder holds everything.
    @discardableResult
    public func syncWidgetLogs() -> Int {
        guard locations.widgetLogs != locations.mirroredWidgetLogs else { return 0 }
        try? fileSystem.createDirectory(at: locations.mirroredWidgetLogs)

        var copied = 0
        for source in logFiles(in: locations.widgetLogs) {
            let destination = locations.mirroredWidgetLogs.appendingPathComponent(source.lastPathComponent)
            if let existing = fileSystem.modificationDate(of: destination),
               let sourceDate = fileSystem.modificationDate(of: source),
               existing >= sourceDate {
                continue
            }
            try? fileSystem.remove(destination)
            if (try? fileSystem.copy(from: source, to: destination)) != nil { copied += 1 }
        }
        return copied
    }

    /// All `.log` files in a directory, oldest first.
    public func logFiles(in directory: URL) -> [URL] {
        let urls = (try? fileSystem.contentsOfDirectory(at: directory)) ?? []
        return urls
            .filter { $0.pathExtension == "log" }
            .sorted { (fileSystem.modificationDate(of: $0) ?? .distantPast) < (fileSystem.modificationDate(of: $1) ?? .distantPast) }
    }

    /// How many log files the app and the widget have written.
    public var logFileCount: Int {
        logFiles(in: locations.appLogs).count + logFiles(in: locations.widgetLogs).count
    }

    /// Merges the app and widget logs into one chronologically sorted JSON file in the temporary
    /// directory, ready to share. Returns `nil` when there is nothing to export.
    ///
    /// The file is `{"export": {…metadata…}, "entries": [ … ]}`. Each entry is the original log
    /// object, one per line, so the file is still easy to grep. A line that is not valid JSON is kept
    /// as `{"raw": "…"}` instead of being dropped.
    ///
    /// - Parameter metadata: extra facts for the `export` object, such as app version and OS version.
    public func combinedLog(metadata: [String: String] = [:]) throws -> URL? {
        LWLogging.flush()
        syncWidgetLogs()

        var lines: [String] = []
        for directory in [locations.appLogs, locations.widgetLogs] {
            for file in logFiles(in: directory) {
                guard let text = try? fileSystem.readString(file) else { continue }
                lines.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
            }
        }
        guard !lines.isEmpty else { return nil }

        // Lines start with a fixed-width ISO timestamp, so a plain sort is chronological.
        lines.sort()

        let entries = lines.map(Self.validJSONObject(_:))
        let now = Date()
        var header = metadata
        header["exportedAt"] = now.formatted(.iso8601)
        header["format"] = "ios-livewire-log/1"
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys, .prettyPrinted])
        let headerText = String(decoding: headerData, as: UTF8.self)

        var output = "{\n\"export\": \(headerText),\n\"entryCount\": \(entries.count),\n\"entries\": [\n"
        output += entries.joined(separator: ",\n")
        output += "\n]\n}\n"

        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        removeOldExports()
        let url = fileSystem.temporaryDirectory.appendingPathComponent("ios-livewire-\(stamp).json")
        try fileSystem.write(Data(output.utf8), to: url)
        return url
    }

    /// The file to share: the combined log, or a placeholder when nothing has been logged yet.
    public func shareFile(metadata: [String: String] = [:]) throws -> URL {
        if let url = try combinedLog(metadata: metadata) { return url }
        let url = fileSystem.temporaryDirectory.appendingPathComponent("ios-livewire-empty.json")
        try fileSystem.write(Data("{\"entryCount\":0,\"entries\":[]}\n".utf8), to: url)
        return url
    }

    /// Deletes every log file (app, widget and mirrored copies).
    public func clear() {
        for directory in [locations.appLogs, locations.widgetLogs, locations.mirroredWidgetLogs] {
            for file in logFiles(in: directory) {
                try? fileSystem.remove(file)
            }
        }
    }

    /// Earlier exports are deleted, so shared copies of the logs do not pile up in the temporary directory.
    private func removeOldExports() {
        let directory = fileSystem.temporaryDirectory
        for url in (try? fileSystem.contentsOfDirectory(at: directory)) ?? [] {
            let name = url.lastPathComponent
            if name.hasPrefix("ios-livewire-"), name.hasSuffix(".json") || name.hasSuffix(".jsonl") {
                try? fileSystem.remove(url)
            }
        }
    }

    /// The line itself when it is a JSON object, else a `{"raw": …}` wrapper around it.
    private static func validJSONObject(_ line: String) -> String {
        if let data = line.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            return line
        }
        let wrapped = (try? JSONSerialization.data(withJSONObject: ["raw": line])) ?? Data("{}".utf8)
        return String(decoding: wrapped, as: UTF8.self)
    }
}
