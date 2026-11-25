import Foundation
import LWAPI
import LWLogging
import LWModels
import LWServices
import WidgetKit

/// Builds the widget's timeline.
///
/// WidgetKit gives each widget a limited daily refresh budget and decides when it actually runs, so
/// the timeline asks for a reload every 15 minutes while charging and every 30 otherwise. The app
/// also reloads timelines whenever it refreshes. Truly live updates would need push-triggered widget
/// reloads, which need a server and are out of scope for this MVP.
struct BatteryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry { .placeholder }

    func snapshot(for configuration: BatteryIntent, in context: Context) async -> BatteryEntry {
        if context.isPreview { return .placeholder }
        return await entry(for: configuration)
    }

    func timeline(for configuration: BatteryIntent, in context: Context) async -> Timeline<BatteryEntry> {
        let entry = await entry(for: configuration)
        LWLogging.flush()  // the extension can be suspended as soon as this returns
        let minutes = entry.status?.isCharging == true ? 15 : 30
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(Double(minutes) * 60)))
    }

    private func entry(for intent: BatteryIntent) async -> BatteryEntry {
        let log = LWLogger("widget")
        let configuration = RuntimeConfiguration(bundle: .main)

        let service = LiveWireService.live(configuration: configuration)
        guard await service.isSignedIn() else {
            log.info("Widget: not signed in")
            return .message(.signedOut)
        }

        var snapshot = await service.cachedSnapshot()
        if snapshot.bikes.isEmpty {
            do { try await service.refreshBikes() } catch { log.error("Widget bike list refresh failed: \(error)") }
            snapshot = await service.cachedSnapshot()
        }

        guard let bikeID = intent.bike?.id ?? snapshot.effectiveBikeID,
              let bike = snapshot.bikes.first(where: { $0.id == bikeID })
        else {
            log.info("Widget: no bike to show")
            return .message(.noBike)
        }
        if bike.isPaired == false { return .message(.notPaired, bikeName: bike.displayName) }

        do {
            let status = try await service.refreshStatus(bikeID: bikeID)
            return BatteryEntry(date: .now, bikeName: bike.displayName, state: .ok, status: status, isStale: false)
        } catch {
            log.warning("Widget refresh for bike \(bikeID) failed: \(error)")
            if let cached = snapshot.statuses[bikeID] {
                return BatteryEntry(date: .now, bikeName: bike.displayName, state: .ok, status: cached, isStale: true)
            }
            return BatteryEntry(
                date: .now, bikeName: bike.displayName,
                state: .failed(error.localizedDescription), status: nil, isStale: false
            )
        }
    }
}
