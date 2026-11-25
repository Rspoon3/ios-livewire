// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiveWireKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LWModels", targets: ["LWModels"]),
        .library(name: "LWLogging", targets: ["LWLogging"]),
        .library(name: "LWSecureStorage", targets: ["LWSecureStorage"]),
        .library(name: "LWAPI", targets: ["LWAPI"]),
        .library(name: "LWStore", targets: ["LWStore"]),
        .library(name: "LWServices", targets: ["LWServices"]),
        .library(name: "LWFeatures", targets: ["LWFeatures"]),
        .library(name: "LWWidgets", targets: ["LWWidgets"]),
    ],
    dependencies: [
        // Persistent, rotating file logging that can be pulled off a device.
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", from: "3.9.0"),
        // Keychain access, including sharing between the app and the widget through an App Group.
        .package(url: "https://github.com/square/Valet.git", from: "5.1.0"),
    ],
    targets: [
        // Pure value types. No dependencies.
        .target(name: "LWModels"),

        // CocoaLumberjack file logging, redaction, export.
        .target(
            name: "LWLogging",
            dependencies: [
                .product(name: "CocoaLumberjackSwift", package: "CocoaLumberjack"),
            ]
        ),

        // Keychain wrapper. Every secret goes through here.
        .target(
            name: "LWSecureStorage",
            dependencies: ["LWLogging", .product(name: "Valet", package: "Valet")]
        ),

        // Gigya login, session token, LiveWire endpoints.
        .target(name: "LWAPI", dependencies: ["LWModels", "LWLogging", "LWSecureStorage"]),

        // On-disk snapshot shared by the app and the widget (App Group container).
        .target(name: "LWStore", dependencies: ["LWModels", "LWLogging"]),

        // Facade that composes API + store + keychain. Used by the app and the widget.
        .target(
            name: "LWServices",
            dependencies: ["LWModels", "LWLogging", "LWSecureStorage", "LWAPI", "LWStore"]
        ),

        // SwiftUI screens and their observable models.
        .target(
            name: "LWFeatures",
            dependencies: ["LWModels", "LWLogging", "LWServices", "LWStore"]
        ),

        // WidgetKit widgets, intents and timeline provider.
        .target(
            name: "LWWidgets",
            dependencies: ["LWModels", "LWLogging", "LWServices", "LWStore"]
        ),

        .testTarget(name: "LWModelsTests", dependencies: ["LWModels"]),
        .testTarget(name: "LWLoggingTests", dependencies: ["LWLogging"]),
        .testTarget(
            name: "LWAPITests",
            dependencies: ["LWAPI", "LWModels", "LWSecureStorage"]
        ),
        .testTarget(name: "LWStoreTests", dependencies: ["LWStore", "LWModels"]),
    ]
)
