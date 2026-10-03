// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyShelf",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure model + storage logic (no UI), so it can be tested headlessly.
        .target(name: "CopyShelfCore"),
        // The menu bar app itself.
        .executableTarget(name: "CopyShelf", dependencies: ["CopyShelfCore"]),
        // Dependency-free test runner (Command Line Tools ship neither XCTest nor Swift Testing).
        .executableTarget(name: "CopyShelfSelfTest", dependencies: ["CopyShelfCore"]),
    ]
)
