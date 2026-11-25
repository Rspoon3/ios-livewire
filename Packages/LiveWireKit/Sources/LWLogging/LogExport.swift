import Foundation

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

public enum LogExport {
    /// Copies the widget's log files next to the app's, so one folder holds everything.
    @discardableResult
    public static func syncWidgetLogs(_ locations: LogLocations) -> Int {
        guard locations.widgetLogs != locations.mirroredWidgetLogs else { return 0 }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: locations.mirroredWidgetLogs, withIntermediateDirectories: true)

        var copied = 0
        for source in logFiles(in: locations.widgetLogs) {
            let destination = locations.mirroredWidgetLogs.appendingPathComponent(source.lastPathComponent)
            let sourceDate = modificationDate(source)
            if let existing = modificationDate(destination), let sourceDate, existing >= sourceDate {
                continue
            }
            try? fileManager.removeItem(at: destination)
            if (try? fileManager.copyItem(at: source, to: destination)) != nil { copied += 1 }
        }
        return copied
    }

    /// All `.log` files in a directory, oldest first.
    public static func logFiles(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "log" }
            .sorted { (modificationDate($0) ?? .distantPast) < (modificationDate($1) ?? .distantPast) }
    }

    /// Merges the app and widget logs into one chronologically sorted JSON file in the temporary
    /// directory, ready to share. Returns `nil` when there is nothing to export.
    ///
    /// The file is `{"export": {…metadata…}, "entries": [ … ]}`. Each entry is the original log
    /// object, one per line, so the file is still easy to grep. A line that is not valid JSON is kept
    /// as `{"raw": "…"}` instead of being dropped.
    ///
    /// - Parameter metadata: extra facts for the `export` object, such as app version and OS version.
    public static func combinedLog(_ locations: LogLocations, metadata: [String: String] = [:]) throws -> URL? {
        LWLogging.flush()
        syncWidgetLogs(locations)

        var lines: [String] = []
        for directory in [locations.appLogs, locations.widgetLogs] {
            for file in logFiles(in: directory) {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                lines.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
            }
        }
        guard !lines.isEmpty else { return nil }

        // Lines start with a fixed-width ISO timestamp, so a plain sort is chronological.
        lines.sort()

        let entries = lines.map(validJSONObject(_:))
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-livewire-\(stamp).json")
        try output.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Earlier exports are deleted, so shared copies of the logs do not pile up in the temporary directory.
    private static func removeOldExports() {
        let directory = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix("ios-livewire-") && (name.hasSuffix(".json") || name.hasSuffix(".jsonl")) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
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

    /// Deletes every log file (app, widget and mirrored copies).
    public static func clear(_ locations: LogLocations) {
        for directory in [locations.appLogs, locations.widgetLogs, locations.mirroredWidgetLogs] {
            for file in logFiles(in: directory) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
