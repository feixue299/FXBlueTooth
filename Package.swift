// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "FXBlueTooth",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "FXBlueToothDSL", targets: ["FXBlueTooth"]),
        .library(name: "FXBlueToothCore", targets: ["FXBlueToothCore"]),
        .library(name: "FXBlueToothAsync", targets: ["FXBlueToothAsync"]),
        .library(name: "FXBlueToothCombine", targets: ["FXBlueToothCombine"]),
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
            name: "FXBlueToothCore",
            dependencies: [],
            path: "FXBlueToothCore"),
        .target(
            name: "FXBlueToothAsync",
            dependencies: ["FXBlueToothCore"],
            path: "FXBlueToothAsync"),
        .target(
            name: "FXBlueToothCombine",
            dependencies: ["FXBlueToothCore"],
            path: "FXBlueToothCombine"),
        .testTarget(
            name: "FXBlueToothAsyncTests",
            dependencies: ["FXBlueToothAsync"],
            path: "Tests/FXBlueToothAsyncTests"),
        .testTarget(
            name: "FXBlueToothCombineTests",
            dependencies: ["FXBlueToothCombine"],
            path: "Tests/FXBlueToothCombineTests"),
    ]
)
