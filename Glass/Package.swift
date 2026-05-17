// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Glass",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Glass", targets: ["Glass"])
    ],
    targets: [
        .executableTarget(
            name: "Glass",
            path: "Sources/Glass"
        )
    ]
)
