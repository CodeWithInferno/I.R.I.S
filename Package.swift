// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LiDARObstacleDetection",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "LiDARObstacleDetection",
            targets: ["LiDARObstacleDetection"]),
    ],
    targets: [
        .target(
            name: "LiDARObstacleDetection",
            path: "Sources")
    ]
)