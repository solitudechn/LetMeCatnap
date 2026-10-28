// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LetMeCatnap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LetMeCatnap", targets: ["LetMeCatnap"]),
        .library(name: "CatnapCore", targets: ["CatnapCore"]),
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
            name: "CatnapCore",
            path: "core"
        ),
        .executableTarget(
            name: "LetMeCatnap",
            dependencies: [
                "CatnapCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "src"
        ),
        .testTarget(
            name: "CatnapCoreTests",
            dependencies: ["CatnapCore"],
            path: "Tests/CatnapCoreTests"
        ),
    ]
)
