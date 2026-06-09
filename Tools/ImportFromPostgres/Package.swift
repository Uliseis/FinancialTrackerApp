// swift-tools-version: 6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "ImportFromPostgres",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ImportFromPostgres", targets: ["ImportFromPostgres"]),
        .library(name: "ImportFromPostgresCore", targets: ["ImportFromPostgresCore"]),
    ],
    dependencies: [
        .package(path: "../../Core"),
    ],
    targets: [
        .target(
            name: "ImportFromPostgresCore",
            dependencies: [
                .product(name: "CoreModel", package: "Core"),
                .product(name: "CoreLogic", package: "Core"),
            ],
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "ImportFromPostgres",
            dependencies: ["ImportFromPostgresCore"],
            swiftSettings: swift5
        ),
        .testTarget(
            name: "ImportFromPostgresCoreTests",
            dependencies: [
                "ImportFromPostgresCore",
                .product(name: "CoreModel", package: "Core"),
                .product(name: "CoreLogic", package: "Core"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: swift5
        ),
    ]
)
