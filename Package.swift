// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FXBlueTooth",
    platforms: [
        .iOS(.v10)
    ],
    products: [
        .library(
            name: "FXBlueTooth",
            targets: ["FXBlueTooth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", from: "1.9.5"),
    ],
    targets: [
        .target(
            name: "FXBlueTooth",
            dependencies: ["SwiftyBeaver"],
            path: "FXBlueTooth"),
    ]
)
