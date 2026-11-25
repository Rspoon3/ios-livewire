import Foundation

/// A bike on the account, with whether this app's device UUID is paired with it.
public struct Bike: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var vin: String?
    public var name: String?
    public var make: String?
    public var model: String?
    public var modelCode: String?
    public var modelNumber: String?
    public var year: Int?
    public var color: String?
    public var isPrimary: Bool
    /// `nil` when the response did not say.
    public var isPaired: Bool?

    public init(
        id: String,
        vin: String? = nil,
        name: String? = nil,
        make: String? = nil,
        model: String? = nil,
        modelCode: String? = nil,
        modelNumber: String? = nil,
        year: Int? = nil,
        color: String? = nil,
        isPrimary: Bool = false,
        isPaired: Bool? = nil
    ) {
        self.id = id
        self.vin = vin
        self.name = name
        self.make = make
        self.model = model
        self.modelCode = modelCode
        self.modelNumber = modelNumber
        self.year = year
        self.color = color
        self.isPrimary = isPrimary
        self.isPaired = isPaired
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        let parts = [make, model].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return "Bike \(id)"
    }
}
