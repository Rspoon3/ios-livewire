import CocoaLumberjackSwift
import Foundation

/// Writes one JSON object per line (JSON Lines).
///
/// The timestamp key comes first and has a fixed width, so lines from several files sort
/// chronologically as plain text. That is what lets `LogExport` merge the app and widget logs.
///
///     {"ts":"2026-11-25T10:46:01.123Z","level":"INFO","process":"app","category":"api","msg":"…","src":"LiveWireAPI.swift:88"}
final class JSONLineFormatter: NSObject, DDLogFormatter, @unchecked Sendable {
    private let process: LogProcess

    init(process: LogProcess) {
        self.process = process
    }

    func format(message logMessage: DDLogMessage) -> String? {
        let timestamp = logMessage.timestamp.formatted(
            Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        )
        let category = (logMessage.representedObject as? String) ?? "app"
        let text = Redactor.scrubTokens(logMessage.message)
        let source = "\(logMessage.fileName):\(logMessage.line)"

        return #"{"ts":"\#(timestamp)","level":"\#(Self.levelName(logMessage.flag))","process":"\#(process.rawValue)","category":\#(Self.json(category)),"msg":\#(Self.json(text)),"src":\#(Self.json(source))}"#
    }

    private static func levelName(_ flag: DDLogFlag) -> String {
        switch flag {
        case .error: "ERROR"
        case .warning: "WARN"
        case .info: "INFO"
        case .debug: "DEBUG"
        default: "TRACE"
        }
    }

    /// A JSON string literal, quotes included.
    private static func json(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }
}
