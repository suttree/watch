// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Watch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WatchCore", targets: ["WatchCore"]),
        .executable(name: "WatchApp", targets: ["WatchApp"])
    ],
    targets: [
        .target(name: "WatchCore"),
        .executableTarget(
            name: "WatchApp",
            dependencies: ["WatchCore"],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "WatchCoreTests",
            dependencies: ["WatchCore"]
        )
    ]
)
