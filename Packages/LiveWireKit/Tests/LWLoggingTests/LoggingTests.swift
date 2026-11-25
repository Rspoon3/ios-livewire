import Foundation
import LWFileSystem
import LWModels
import Testing

@testable import LWLogging

@Suite struct RedactorTests {
    static let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0LXVzZXIifQ.c2lnbmF0dXJl"

    @Test func masksSensitiveKeysAtAnyDepth() {
        let body = Data(#"{"jwt":"abc","user":{"Password":"hunter2","uid":"u-1","name":"ok"},"list":[{"token":"t"}],"battery":82}"#.utf8)
        let text = Redactor.redactedBody(body)
        #expect(!text.contains("hunter2"))
        #expect(!text.contains("u-1"))
        #expect(!text.contains("\"abc\""))
        #expect(!text.contains("\"t\""))
        #expect(text.contains("\"name\":\"ok\""))
        #expect(text.contains("\"battery\":82"))
    }

    @Test func masksTheVINAndGPSPositions() {
        let body = Data(#"{"bikes":[{"id":"1","vin":"1HD0TESTVIN000000","model":"S2"}],"location":{"latitude":37.5,"longitude":-122.2},"ride":{"coordinates":[[1,2]],"distance":12}}"#.utf8)
        let text = Redactor.redactedBody(body)
        #expect(!text.contains("TESTVIN"))
        #expect(!text.contains("37.5"))
        #expect(!text.contains("-122.2"))
        #expect(!text.contains("[1,2]"))
        // Everything else is still there, because the log exists to map the API.
        #expect(text.contains("\"model\":\"S2\""))
        #expect(text.contains("\"distance\":12"))
    }

    @Test func errorCodesStayVisible() {
        let body = Data(#"{"error":{"code":"3000","description":"Command manager api failed"}}"#.utf8)
        let text = Redactor.redactedBody(body)
        #expect(text.contains("3000"))
        #expect(text.contains("Command manager api failed"))
    }

    @Test func extraKeysAreMasked() {
        let body = Data(#"{"code":"123456"}"#.utf8)
        #expect(Redactor.redactedBody(body, extraKeys: ["code"]).contains("123456") == false)
        #expect(Redactor.redactedBody(body).contains("123456"))
    }

    @Test func scrubsJWTsAndBearerInFreeText() {
        let text = Redactor.scrubTokens("Authorization: Bearer \(Self.jwt) and also \(Self.jwt)")
        #expect(!text.contains("eyJ"))
        #expect(text.contains("Bearer <redacted>"))
    }

    @Test func jwtInsideAStringValueIsMasked() {
        let body = Data(#"{"note":"\#(Self.jwt)"}"#.utf8)
        #expect(!Redactor.redactedBody(body).contains("eyJ"))
    }

    @Test func truncatesHugeBodies() {
        let big = Data(#"{"x":"\#(String(repeating: "a", count: 500))"}"#.utf8)
        let text = Redactor.redactedBody(big, limit: 100)
        #expect(text.contains("truncated"))
        #expect(text.count < 200)
    }

    @Test func binaryAndEmptyBodies() {
        #expect(Redactor.redactedBody(Data()) == "<empty>")
        #expect(Redactor.redactedBody(Data([0xFF, 0xFE, 0x00])).contains("binary"))
    }
}

/// Logging is process-global (CocoaLumberjack), so everything that touches it lives in one test.
@Suite(.serialized) struct FileLoggingTests {
    @Test func writesRedactedJSONLinesToDisk() throws {
        // Lumberjack writes to the real disk, so this one test uses it.
        let disk = DiskFileSystem()
        let locations = LogLocations(documents: disk.temporaryDirectory, sharedContainer: nil)
        let directory = disk.temporaryDirectory
            .appendingPathComponent("lw-logging-\(UUID().uuidString)", isDirectory: true)
        defer { try? disk.remove(directory) }

        LWLogging.bootstrap(process: .app, directory: directory, fileSystem: disk)
        let log = LWLogger("test")
        log.info("hello world")
        log.warning("token leak \(RedactorTests.jwt)")
        log.error("with \"quotes\" and\nnewline")
        LWLogging.flush()

        // DDFileLogger writes on its own queue; give it a moment after the flush.
        var files: [URL] = []
        for _ in 0..<50 {
            files = LogExport(locations: locations, fileSystem: disk).logFiles(in: directory)
            if let first = files.first, (try? disk.read(first))?.isEmpty == false { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let file = try #require(files.first)
        let text = try disk.readString(file)
        #expect(!text.contains("eyJ"), "JWT leaked into the log file")

        let lines = text.split(separator: "\n")
        #expect(lines.count >= 3)
        for line in lines {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(object["ts"] is String)
            #expect(object["level"] is String)
            #expect(object["process"] as? String == "app")
        }

        let hello = try #require(lines.compactMap { line -> [String: Any]? in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }.first { $0["msg"] as? String == "hello world" })
        #expect(hello["category"] as? String == "test")
        #expect(hello["level"] as? String == "INFO")
    }

}

@Suite struct LogExportTests {
    private let locations = LogLocations(
        documents: URL(filePath: "/memory/Documents"),
        sharedContainer: URL(filePath: "/memory/Group")
    )

    private func export(_ files: InMemoryFileSystem) -> LogExport {
        LogExport(locations: locations, fileSystem: files)
    }

    private func seed(_ files: InMemoryFileSystem) throws {
        try files.write(Data(#"{"ts":"2026-11-25T10:00:02.000Z","msg":"app late"}"#.utf8), to: locations.appLogs.appendingPathComponent("a.log"))
        try files.write(Data(#"{"ts":"2026-11-25T10:00:01.000Z","msg":"widget early"}"#.utf8), to: locations.widgetLogs.appendingPathComponent("w.log"))
        // A corrupt line must survive as {"raw": …}, not break the file.
        try files.write(Data("not json at all".utf8), to: locations.appLogs.appendingPathComponent("b.log"))
    }

    @Test func combinedExportMergesAndSorts() throws {
        let files = InMemoryFileSystem()
        try seed(files)

        let url = try #require(try export(files).combinedLog(metadata: ["app": "test"]))

        #expect(url.pathExtension == "json")
        #expect(url.deletingLastPathComponent() == files.temporaryDirectory)
        let document = try #require(try JSONSerialization.jsonObject(with: files.read(url)) as? [String: Any])
        #expect(document["entryCount"] as? Int == 3)
        #expect((document["export"] as? [String: Any])?["app"] as? String == "test")
        let entries = try #require(document["entries"] as? [[String: Any]])
        #expect(entries.compactMap { $0["msg"] as? String } == ["widget early", "app late"])
        #expect(entries.contains { $0["raw"] as? String == "not json at all" })

        // The widget file is mirrored next to the app's files.
        #expect(export(files).logFiles(in: locations.mirroredWidgetLogs).count == 1)
    }

    @Test func aNewExportReplacesTheOldOne() throws {
        let files = InMemoryFileSystem()
        try seed(files)
        let old = files.temporaryDirectory.appendingPathComponent("ios-livewire-20200101T000000Z.json")
        try files.write(Data("{}".utf8), to: old)

        _ = try export(files).combinedLog()

        #expect(!files.fileExists(at: old))
        #expect(files.allFilePaths.filter { $0.hasSuffix(".json") }.count == 1)
    }

    @Test func nothingLoggedYetStillGivesAFileToShare() throws {
        let files = InMemoryFileSystem()
        #expect(try export(files).combinedLog() == nil)

        let url = try export(files).shareFile()

        let document = try #require(try JSONSerialization.jsonObject(with: files.read(url)) as? [String: Any])
        #expect(document["entryCount"] as? Int == 0)
    }

    @Test func mirroringCopiesOnlyNewerWidgetFiles() throws {
        let files = InMemoryFileSystem()
        try seed(files)
        let export = export(files)
        #expect(export.syncWidgetLogs() == 1)
        #expect(export.syncWidgetLogs() == 0, "the copy is up to date")

        // The widget logs more.
        let source = locations.widgetLogs.appendingPathComponent("w.log")
        try files.write(Data("{\"ts\":\"2026-11-25T10:00:09.000Z\"}".utf8), to: source)
        files.setModificationDate(Date().addingTimeInterval(60), of: source)
        #expect(export.syncWidgetLogs() == 1)
    }

    @Test func filesAreListedOldestFirstAndOnlyLogs() throws {
        let files = InMemoryFileSystem()
        let directory = locations.appLogs
        try files.write(Data(), to: directory.appendingPathComponent("new.log"))
        try files.write(Data(), to: directory.appendingPathComponent("old.log"))
        try files.write(Data(), to: directory.appendingPathComponent("notes.txt"))
        files.setModificationDate(Date(timeIntervalSince1970: 100), of: directory.appendingPathComponent("old.log"))
        files.setModificationDate(Date(timeIntervalSince1970: 200), of: directory.appendingPathComponent("new.log"))

        let names = export(files).logFiles(in: directory).map(\.lastPathComponent)

        #expect(names == ["old.log", "new.log"])
    }

    @Test func clearRemovesEveryLogFile() throws {
        let files = InMemoryFileSystem()
        try seed(files)
        let export = export(files)
        export.syncWidgetLogs()
        #expect(export.logFileCount > 0)

        export.clear()

        #expect(export.logFileCount == 0)
        #expect(export.logFiles(in: locations.mirroredWidgetLogs).isEmpty)
    }

    @Test func aFailedWriteIsReportedNotSwallowed() throws {
        let files = InMemoryFileSystem()
        try seed(files)
        files.failNext(.write, with: CocoaError(.fileWriteOutOfSpace))

        #expect(throws: CocoaError.self) { try export(files).combinedLog() }
    }
}
