// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftGH",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "SwiftGHCore", targets: ["SwiftGHCore"]),
        .library(name: "SwiftGHCommand", targets: ["SwiftGHCommand"]),
        .executable(name: "gh", targets: ["gh"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser",
                 from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log",
                 from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftGHCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SwiftGHCore"
        ),
        .target(
            name: "SwiftGHCommand",
            dependencies: [
                "SwiftGHCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SwiftGHCommand"
        ),
        .executableTarget(
            name: "gh",
            dependencies: [
                "SwiftGHCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/gh"
        ),
        .testTarget(
            name: "SwiftGHCoreTests",
            dependencies: ["SwiftGHCore"],
            path: "Tests/SwiftGHCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "SwiftGHCommandTests",
            dependencies: ["SwiftGHCommand", "SwiftGHCore"],
            path: "Tests/SwiftGHCommandTests"
        ),
    ]
)
