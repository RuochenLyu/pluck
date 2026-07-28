// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pluck",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PluckKit", targets: ["PluckKit"]),
        .executable(name: "pluck", targets: ["PluckCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(name: "PluckKit"),
        .executableTarget(
            name: "PluckCLI",
            dependencies: [
                "PluckKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            // A symlink to models/manifest.json, which stays the single copy: the CLI has
            // to carry the manifest in its own binary (product-plan §4.8 — the manifest is
            // trusted because it ships signed, never fetched), and SwiftPM only accepts
            // resources living inside the target's directory.
            resources: [.copy("Resources/manifest.json")]
        ),
        .executableTarget(
            name: "PluckApp",
            dependencies: ["PluckKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PluckKitTests", dependencies: ["PluckKit"]),
        .testTarget(name: "PluckAppTests", dependencies: ["PluckApp"]),
        .testTarget(name: "PluckCLITests", dependencies: ["PluckCLI"])
    ]
)
