// swift-tools-version: 6.0
import PackageDescription

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
        .target(name: "CoreModel"),
        .target(name: "CoreLogic", dependencies: ["CoreModel"]),
        .target(name: "CoreIntegrations", dependencies: ["CoreModel"]),
        .target(name: "CoreSync", dependencies: ["CoreModel", "CoreIntegrations"]),

        .testTarget(name: "CoreModelTests", dependencies: ["CoreModel"]),
        .testTarget(name: "CoreLogicTests", dependencies: ["CoreLogic", "CoreModel"]),
        .testTarget(name: "CoreIntegrationsTests", dependencies: ["CoreIntegrations", "CoreModel"]),
        .testTarget(name: "CoreSyncTests", dependencies: ["CoreSync", "CoreModel"]),
    ]
)
