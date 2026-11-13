// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-2.0-only
import PackageDescription

let package = Package(
    name: "SFTCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SFTCore", targets: ["SFTCore"])],
    targets: [
        .target(name: "SFTCore"),
        .testTarget(name: "SFTCoreTests", dependencies: ["SFTCore"]),
    ]
)
