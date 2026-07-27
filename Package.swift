// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pluck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PluckKit", targets: ["PluckKit"])
    ],
    targets: [
        .target(name: "PluckKit"),
        .testTarget(name: "PluckKitTests", dependencies: ["PluckKit"])
    ]
)
