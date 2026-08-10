// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pluck",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "PluckKit", targets: ["PluckKit"]),
        .executable(name: "pluck", targets: ["PluckCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // The app target's only third-party dependency, and deliberately the last one
        // (decisions.md 2026-07-28): updating a non-App-Store Mac app is a signature-checking,
        // privilege-separated, relaunch-safe problem, and Sparkle is the answer everyone else
        // already reviewed. PluckKit and the CLI do not see it — nothing in the engine or in
        // an agent's `pluck` invocation should be able to reach an updater.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.4")
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
            dependencies: [
                "PluckKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PluckKitTests", dependencies: ["PluckKit"]),
        .testTarget(name: "PluckAppTests", dependencies: ["PluckApp"]),
        .testTarget(name: "PluckCLITests", dependencies: ["PluckCLI"])
    ]
)
