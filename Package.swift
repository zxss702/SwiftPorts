// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SwiftGH",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
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
        .package(url: "https://github.com/apple/swift-http-types",
                 from: "1.3.0"),
        // YAML trait pulls in `FileProvider<YAMLSnapshot>` for reading
        // ~/.config/gh/config.yml and hosts.yml later. CommandLineArguments
        // trait gives us a uniform precedence chain (CLI > env > file).
        .package(url: "https://github.com/apple/swift-configuration",
                 from: "1.2.0",
                 traits: [.defaults, "YAML", "CommandLineArguments"]),
        // swift-crypto exposes the same API as CryptoKit but works on Linux
        // too. Used by the future OAuth flow (PKCE = SHA-256 of a verifier).
        .package(url: "https://github.com/apple/swift-crypto",
                 from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftGHCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Crypto", package: "swift-crypto"),
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
