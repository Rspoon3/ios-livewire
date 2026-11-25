import CocoaLumberjackSwift
import Foundation

/// Which process is writing. The widget extension runs in its own process, so it logs to its own
/// directory; the app mirrors those files into its Documents folder (see `LogExport`).
public enum LogProcess: String, Sendable {
    case app
    case widget
}

/// Persistent logging on top of CocoaLumberjack.
///
/// Files are JSON Lines, rotate daily or at 5 MB, and are capped at 14 files / 50 MB per process.
/// They are meant to be pulled off a device and read (see `docs/logging.md`).
public enum LWLogging {
    nonisolated(unsafe) private static var fileLogger: DDFileLogger?
    private static let lock = NSLock()

    /// Call once, as early as possible, in every process (app and widget extension).
    /// Calling it again is a no-op.
    public static func bootstrap(process: LogProcess, directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard fileLogger == nil else { return }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Readable once the phone has been unlocked after boot, so the widget can log while it is locked.
        let manager = DDLogFileManagerDefault(
            logsDirectory: directory.path,
            defaultFileProtectionLevel: .completeUntilFirstUserAuthentication
        )
        manager.maximumNumberOfLogFiles = 14
        manager.logFilesDiskQuota = 50 * 1024 * 1024

        let logger = DDFileLogger(logFileManager: manager)
        logger.rollingFrequency = 60 * 60 * 24
        logger.maximumFileSize = 5 * 1024 * 1024
        logger.logFormatter = JSONLineFormatter(process: process)
        DDLog.add(logger, with: .all)
        fileLogger = logger

        #if DEBUG
        // Also mirror to the Xcode console. The file is the source of truth.
        DDLog.add(DDOSLogger.sharedInstance, with: .all)
        #endif

        LWLogger("logging").info("Logging started (process: \(process.rawValue), directory: \(directory.lastPathComponent))")
    }

    /// Writes buffered messages to disk. Call before a widget timeline returns, because the
    /// extension process can be suspended right after.
    public static func flush() {
        DDLog.flushLog()
    }
}

/// A category-tagged logger. Cheap to create; keep one per subsystem.
public struct LWLogger: Sendable {
    public let category: String

    public init(_ category: String) {
        self.category = category
    }

    public func debug(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(message(), flag: .debug, file: file, function: function, line: line)
    }

    public func info(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(message(), flag: .info, file: file, function: function, line: line)
    }

    public func warning(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(message(), flag: .warning, file: file, function: function, line: line)
    }

    public func error(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        emit(message(), flag: .error, file: file, function: function, line: line)
    }

    private func emit(_ text: String, flag: DDLogFlag, file: String, function: String, line: UInt) {
        let message = DDLogMessage(
            format: text,
            formatted: text,
            level: .all,
            flag: flag,
            context: 0,
            file: file,
            function: function,
            line: line,
            tag: category,
            options: [],
            timestamp: nil
        )
        DDLog.sharedInstance.log(asynchronous: true, message: message)
    }
}
