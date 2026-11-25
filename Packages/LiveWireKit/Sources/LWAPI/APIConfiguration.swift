import Foundation

/// What this client tells the backend about itself.
///
/// These are py-livewire's values (an Android Pixel 8), which are known to work with the backend.
/// A first version identified itself as an iPhone; its pairing request was never answered by the
/// bike, while py-livewire's identical request worked. The iOS values are the main remaining
/// difference between the two, so this client uses the known-good ones.
public struct ClientIdentity: Sendable, Equatable {
    public var userAgent: String
    public var model: String
    public var osVersion: String
    public var language: String

    public init(
        userAgent: String = "Android",
        model: String = "Google Pixel 8",
        osVersion: String = "34",
        language: String = "en-US"
    ) {
        self.userAgent = userAgent
        self.model = model
        self.osVersion = osVersion
        self.language = language
    }

    var headers: [String: String] {
        [
            "User-Agent": userAgent,
            "Content-Type": "application/json",
            "Accept-Language": language,
            "model": model,
            "osVersion": osVersion,
        ]
    }
}

public struct APIConfiguration: Sendable {
    public var baseURL: URL
    public var gigyaURL: URL
    /// The Gigya API key LiveWire's own app signs in with. It is a client identifier, not a user
    /// credential, and the same for every user. py-livewire documents it in `const.py`.
    public static let defaultGigyaAPIKey = "4_6aX8cf8RFVt6F3JQQZaF3A"

    public var gigyaAPIKey: String
    public var dataCenter: String
    public var brand: String
    public var identity: ClientIdentity

    public init(
        gigyaAPIKey: String = APIConfiguration.defaultGigyaAPIKey,
        baseURL: URL = URL(string: "https://mobileapi.livewire.com/api")!,
        gigyaURL: URL = URL(string: "https://accounts.us1.gigya.com")!,
        dataCenter: String = "us1",
        brand: String = "LiveWire",
        identity: ClientIdentity = ClientIdentity()
    ) {
        self.gigyaAPIKey = gigyaAPIKey
        self.baseURL = baseURL
        self.gigyaURL = gigyaURL
        self.dataCenter = dataCenter
        self.brand = brand
        self.identity = identity
    }
}
