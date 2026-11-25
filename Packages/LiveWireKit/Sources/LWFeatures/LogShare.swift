import CoreTransferable
import LWLogging
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A log export the share sheet builds only when it is opened, so one tap on the share button is
/// all it takes. The file merges the app and widget logs, sorted by time.
struct LogShareItem: Transferable {
    let locations: LogLocations

    /// What the person reading the log needs to know. No names or identifiers.
    static var metadata: [String: String] {
        let info = Bundle.main.infoDictionary
        return [
            "app": Bundle.main.bundleIdentifier ?? "unknown",
            "appVersion": info?["CFBundleShortVersionString"] as? String ?? "?",
            "build": info?["CFBundleVersion"] as? String ?? "?",
            "os": "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "device": UIDevice.current.model,
        ]
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            do {
                if let url = try LogExport.combinedLog(item.locations, metadata: Self.metadata) { return SentTransferredFile(url) }
            } catch {
                LWLogger("share").error("Preparing the log export failed: \(error)")
                throw error
            }
            // Nothing logged yet. Share a one-line file rather than failing.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ios-livewire-empty.json")
            try Data("{\"entryCount\":0,\"entries\":[]}\n".utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// One-tap log sharing. Available on every screen, including setup and sign-in, because that is
/// where the first failures show up.
struct LogShareButton: View {
    let model: AppModel

    var body: some View {
        ShareLink(
            item: LogShareItem(locations: model.logLocations),
            preview: SharePreview("ios-livewire logs", image: Image(systemName: "doc.text"))
        ) {
            Label("Share logs", systemImage: "square.and.arrow.up")
        }
    }
}
