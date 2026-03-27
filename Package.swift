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
    targets: [
        .executableTarget(
            name: "PTS",
            path: "Sources/PTS",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
