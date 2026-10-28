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
    dependencies: [
        // Updates are handled by Sparkle rather than by hand: it is the
        // de-facto standard for non-App-Store Mac apps, signs every release
        // with an Ed25519 key, and asks for an admin password instead of
        // silently failing when /Applications is not writable.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure Foundation logic: settings storage, timing rules and the string
        // table. Kept free of AppKit/SwiftUI so it can be unit-tested anywhere,
        // including in CI.
        .target(
            name: "ICHRCore",
            path: "core"
        ),
        .executableTarget(
            name: "iCanHazRepose",
            dependencies: [
                "ICHRCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "src"
        ),
        .testTarget(
            name: "ICHRCoreTests",
            dependencies: ["ICHRCore"],
            path: "Tests/ICHRCoreTests"
        ),
    ]
)
