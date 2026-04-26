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
        .library(name: "FXBlueToothAsync", targets: ["FXBlueToothAsync"]),
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
        .testTarget(
            name: "FXBlueToothAsyncTests",
            dependencies: ["FXBlueToothAsync"],
            path: "Tests/FXBlueToothAsyncTests"),
    ]
)
