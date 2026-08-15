// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "ScreenFix",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ScreenFixCore", targets: ["ScreenFixCore"]),
        .executable(name: "ScreenFix", targets: ["ScreenFixLauncher"]),
        .executable(name: "ScreenFixTests", targets: ["ScreenFixTests"]),
    ],
    targets: [
        .target(name: "ScreenFixCore"),
        .target(name: "ScreenFixApp", dependencies: ["ScreenFixCore"]),
        .executableTarget(name: "ScreenFixLauncher", dependencies: ["ScreenFixApp"]),
        .executableTarget(
            name: "ScreenFixTests",
            dependencies: ["ScreenFixCore", "ScreenFixApp"],
            path: "Tests/ScreenFixTests"
        ),
    ]
)
