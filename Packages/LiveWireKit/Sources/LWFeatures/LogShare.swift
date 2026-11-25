import CoreTransferable
import LWLogging
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A log export the share sheet builds only when it is opened, so one tap on the share button is
/// all it takes. The file merges the app and widget logs, sorted by time.
struct LogShareItem: Transferable {
    let export: LogExport

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
                return SentTransferredFile(try item.export.shareFile(metadata: Self.metadata))
            } catch {
                LWLogger("share").error("Preparing the log export failed: \(error)")
                throw error
            }
        }
    }
}

/// One-tap log sharing. Available on every screen, including setup and sign-in, because that is
/// where the first failures show up.
struct LogShareButton: View {
    let export: LogExport

    var body: some View {
        ShareLink(
            item: LogShareItem(export: export),
            preview: SharePreview("ios-livewire logs", image: Image(systemName: "doc.text"))
        ) {
            Label("Share logs", systemImage: "square.and.arrow.up")
        }
    }
}
