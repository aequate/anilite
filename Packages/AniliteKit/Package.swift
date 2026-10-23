// swift-tools-version:5.10
import PackageDescription

// AniliteKit holds everything that doesn't need UIKit/SwiftUI: AniList networking,
// caching, persistence, and the engines behind discovery, spoilers, planning and taste.
// It builds on Linux too, so the logic can be tested without a Mac.
let package = Package(
    name: "AniliteKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AniliteKit", targets: ["AniliteKit"])
    ],
    targets: [
        .target(name: "AniliteKit"),
        .testTarget(
            name: "AniliteKitTests",
            dependencies: ["AniliteKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
