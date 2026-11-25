import AppIntents
import Foundation
import LWModels
import LWServices
import LWStore

/// A bike the widget can be pointed at. Multiple bikes: each widget instance can show a different one.
public struct BikeEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bike")
    public static let defaultQuery = BikeQuery()

    public var id: String
    public var name: String

    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ bike: Bike) {
        self.init(id: bike.id, name: bike.displayName)
    }
}

/// Reads the bike list from the shared snapshot, so choosing a bike in the widget editor works
/// offline and without a network call.
public struct BikeQuery: EntityQuery {
    public init() {}

    private func bikes() async -> [Bike] {
        let configuration = RuntimeConfiguration(bundle: .main)
        let store = SnapshotStore(directory: configuration.snapshotDirectory())
        return await store.load().bikes
    }

    public func entities(for identifiers: [String]) async throws -> [BikeEntity] {
        await bikes().filter { identifiers.contains($0.id) }.map(BikeEntity.init)
    }

    public func suggestedEntities() async throws -> [BikeEntity] {
        await bikes().filter { $0.isPaired != false }.map(BikeEntity.init)
    }

    public func defaultResult() async -> BikeEntity? {
        try? await suggestedEntities().first
    }
}

public struct BatteryIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Bike battery"
    public static let description = IntentDescription("Shows the battery level of one of your bikes.")

    @Parameter(title: "Bike")
    public var bike: BikeEntity?

    public init() {}
}
