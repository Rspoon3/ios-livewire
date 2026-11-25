import Foundation
import LWAPI
import LWLogging
import LWModels

/// One line of the diagnostics report.
public struct DiagnosticLine: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let name: String
    public let outcome: String
    public let isOK: Bool
}

extension LiveWireService {
    /// Asks the backend what it can say about a bike without needing a pairing: whether this install
    /// is paired, and the data py-livewire says is served to unpaired devices (position, tire pressure).
    ///
    /// Nothing here changes anything. Every response body goes to the log, so a recent timestamp in
    /// the location or tire pressure data shows that the bike is reporting to the cloud.
    public func diagnose(bike: Bike) async -> [DiagnosticLine] {
        let log = LWLogger("diagnostics")
        let uuid = (try? await api.currentDeviceUUID()) ?? "?"
        log.info("Diagnostics for bike \(bike.id), device UUID \(uuid)")

        var checks: [(String, String, [(String, String)])] = [
            ("Paired with this device?", "bikes/pairing/status/\(bike.id)", [("deviceUUID", uuid)]),
            ("Location", "bike/\(bike.id)/location", []),
            ("Charging status", "bikes/\(bike.id)/charging/status", [("deviceUUID", uuid)]),
        ]
        if let code = bike.modelCode {
            checks.insert(("Tire pressure", "bikes/\(bike.id)/status/tpms", [("modelCode", code)]), at: 2)
        }

        var lines: [DiagnosticLine] = []
        for (name, path, query) in checks {
            do {
                let body = try await api.probe(path, query: query)
                let line = Self.summarize(name: name, body: body)
                log.info("\(name): \(line.outcome)")
                lines.append(line)
            } catch {
                log.error("\(name) failed: \(error)")
                lines.append(DiagnosticLine(name: name, outcome: error.localizedDescription, isOK: false))
            }
        }
        return lines
    }

    static func summarize(name: String, body: JSONValue) -> DiagnosticLine {
        if let error = body["error"]?.objectValue, !error.isEmpty {
            let code = error["code"]?.textValue ?? "?"
            if code != "0" {
                let description = error["description"]?.textValue ?? "no description"
                return DiagnosticLine(name: name, outcome: "Error \(code): \(description)", isOK: false)
            }
        }
        if let status = body["status"]?.intValue, status != 200 {
            let reason = body["detail"]?.textValue ?? ""
            return DiagnosticLine(name: name, outcome: "Status \(status) \(reason)".trimmingCharacters(in: .whitespaces), isOK: false)
        }
        if let paired = body["pairingStatus"]?.boolValue {
            return DiagnosticLine(name: name, outcome: paired ? "Yes" : "No", isOK: paired)
        }
        let keys = body.objectValue?.keys.sorted().prefix(8).joined(separator: ", ") ?? "no object"
        return DiagnosticLine(name: name, outcome: "Answered (\(keys))", isOK: true)
    }
}
