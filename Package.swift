// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FXBlueTooth",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "FXBlueTooth",
            targets: ["FXBlueTooth"]),
        .library(
            name: "FXBlueToothDSL",
            targets: ["FXBlueTooth"]),
        .library(
            name: "FXBlueToothAsync",
            targets: ["FXBlueToothAsync"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", from: "1.9.5"),
    ],
    targets: [
        .target(
            name: "FXBlueTooth",
            dependencies: ["SwiftyBeaver"],
            path: "FXBlueTooth"),
        .target(
            name: "FXBlueToothAsync",
            dependencies: [],
            path: "FXBlueToothAsync"),
    ]
)
