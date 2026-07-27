// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pluck",
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
            ]
        ),
        .testTarget(name: "PluckKitTests", dependencies: ["PluckKit"]),
        .testTarget(name: "PluckCLITests", dependencies: ["PluckCLI"])
    ]
)
