// swift-tools-version: 6.2
import PackageDescription

// The app runs on the main actor unless it says otherwise; VigilCore stays nonisolated.
// Sparkle, the one dependency, brings updates from GitHub Releases.
let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "VigilCore"),
        .executableTarget(
            name: "Vigil", dependencies: ["VigilCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "VigilCoreTests", dependencies: ["VigilCore"]),
        .testTarget(name: "ConventionTests"),
    ]
)
