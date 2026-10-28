// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "iCanHazRepose",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "iCanHazRepose", targets: ["iCanHazRepose"]),
        .library(name: "ICHRCore", targets: ["ICHRCore"]),
    ],
    dependencies: [],
    targets: [
        // Pure Foundation logic: settings storage and timing rules. Kept free of
        // AppKit/SwiftUI so it can be unit-tested anywhere, including in CI.
        .target(
            name: "ICHRCore",
            path: "core"
        ),
        .executableTarget(
            name: "iCanHazRepose",
            dependencies: ["ICHRCore"],
            path: "src"
        ),
        .testTarget(
            name: "ICHRCoreTests",
            dependencies: ["ICHRCore"],
            path: "Tests/ICHRCoreTests"
        ),
    ]
)
