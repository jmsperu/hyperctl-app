// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HyperCtl",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HyperCtl",
            path: "HyperCtl"
        )
    ]
)
