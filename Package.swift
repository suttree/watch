// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Watch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WatchCore", targets: ["WatchCore"]),
        .executable(name: "WatchApp", targets: ["WatchApp"]),
        .executable(name: "WatchExport", targets: ["WatchExport"])
    ],
    targets: [
        .target(name: "WatchCore"),
        .executableTarget(name: "WatchExport", dependencies: ["WatchCore"]),
        .executableTarget(
            name: "WatchApp",
            dependencies: ["WatchCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WatchCoreTests",
            dependencies: ["WatchCore"]
        ),
        .testTarget(
            name: "WatchAppTests",
            dependencies: ["WatchApp"]
        )
    ]
)
