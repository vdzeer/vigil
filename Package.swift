// swift-tools-version: 6.2
import PackageDescription

// The app runs on the main actor unless it says otherwise; VigilCore stays nonisolated.
let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "VigilCore"),
        .executableTarget(
            name: "Vigil", dependencies: ["VigilCore"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "VigilCoreTests", dependencies: ["VigilCore"]),
        .testTarget(name: "ConventionTests"),
    ]
)
