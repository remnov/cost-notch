// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CostNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CostNotch", targets: ["CostNotch"]),
        .library(name: "CursorCostCore", targets: ["CursorCostCore"]),
    ],
    targets: [
        .target(
            name: "CursorCostCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "CostNotch",
            dependencies: ["CursorCostCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "CursorCostCoreTests",
            dependencies: ["CursorCostCore"]
        ),
    ]
)
