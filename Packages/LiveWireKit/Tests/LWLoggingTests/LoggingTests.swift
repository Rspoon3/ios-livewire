import Foundation
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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lw-logging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        LWLogging.bootstrap(process: .app, directory: directory)
        let log = LWLogger("test")
        log.info("hello world")
        log.warning("token leak \(RedactorTests.jwt)")
        log.error("with \"quotes\" and\nnewline")
        LWLogging.flush()

        // DDFileLogger writes on its own queue; give it a moment after the flush.
        var files: [URL] = []
        for _ in 0..<50 {
            files = LogExport.logFiles(in: directory)
            if let first = files.first, (try? Data(contentsOf: first))?.isEmpty == false { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let file = try #require(files.first)
        let text = try String(contentsOf: file, encoding: .utf8)
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

    @Test func combinedExportMergesAndSorts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lw-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = LogLocations(documents: root.appendingPathComponent("Documents"), sharedContainer: root.appendingPathComponent("Group"))
        try FileManager.default.createDirectory(at: locations.appLogs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.widgetLogs, withIntermediateDirectories: true)

        try #"{"ts":"2026-11-25T10:00:02.000Z","msg":"app late"}"#.write(to: locations.appLogs.appendingPathComponent("a.log"), atomically: true, encoding: .utf8)
        try #"{"ts":"2026-11-25T10:00:01.000Z","msg":"widget early"}"#.write(to: locations.widgetLogs.appendingPathComponent("w.log"), atomically: true, encoding: .utf8)

        // A corrupt line must survive as {"raw": …}, not break the file.
        try "not json at all".write(to: locations.appLogs.appendingPathComponent("b.log"), atomically: true, encoding: .utf8)

        let url = try #require(try LogExport.combinedLog(locations, metadata: ["app": "test"]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.pathExtension == "json")
        let document = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(document["entryCount"] as? Int == 3)
        #expect((document["export"] as? [String: Any])?["app"] as? String == "test")
        let entries = try #require(document["entries"] as? [[String: Any]])
        #expect(entries.compactMap { $0["msg"] as? String } == ["widget early", "app late"])
        #expect(entries.contains { $0["raw"] as? String == "not json at all" })

        // The widget file is mirrored next to the app's files.
        #expect(LogExport.logFiles(in: locations.mirroredWidgetLogs).count == 1)
    }
}
