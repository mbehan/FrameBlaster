// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FrameBlaster",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "FrameBlaster",
            targets: ["FrameBlaster"]
        ),
    ],
    targets: [
        .target(
            name: "FrameBlaster"
        ),
    ],
    swiftLanguageModes: [.v6]
)
