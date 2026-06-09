// swift-tools-version: 6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Core",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "CoreModel", targets: ["CoreModel"]),
        .library(name: "CoreLogic", targets: ["CoreLogic"]),
        .library(name: "CoreIntegrations", targets: ["CoreIntegrations"]),
        .library(name: "CoreSync", targets: ["CoreSync"]),
    ],
    targets: [
        .target(name: "CoreModel", swiftSettings: swift5),
        .target(name: "CoreLogic", dependencies: ["CoreModel"], swiftSettings: swift5),
        .target(name: "CoreIntegrations", dependencies: ["CoreModel"], swiftSettings: swift5),
        .target(name: "CoreSync", dependencies: ["CoreModel", "CoreLogic", "CoreIntegrations"], swiftSettings: swift5),

        .testTarget(name: "CoreModelTests", dependencies: ["CoreModel"], swiftSettings: swift5),
        .testTarget(
            name: "CoreLogicTests",
            dependencies: ["CoreLogic", "CoreModel"],
            resources: [.copy("Fixtures")],
            swiftSettings: swift5
        ),
        .testTarget(name: "CoreIntegrationsTests", dependencies: ["CoreIntegrations", "CoreModel"], swiftSettings: swift5),
        .testTarget(name: "CoreSyncTests", dependencies: ["CoreSync", "CoreModel", "CoreLogic"], swiftSettings: swift5),
    ]
)
