// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PTS",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "PTS",
            targets: ["PTS"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.5.0")
    ],
    targets: [
        .executableTarget(
            name: "PTS",
            dependencies: ["Sparkle"],
            path: "Sources/PTS",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
