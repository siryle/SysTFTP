// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SysTFTP",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SysTFTP",
            targets: ["SysTFTP"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SysTFTP",
            dependencies: [],
            path: "SysTFTP",
            exclude: [
                "Resources/Info.plist",
                "Resources/SysTFTP.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "SysTFTPTests",
            dependencies: ["SysTFTP"],
            path: "Tests"
        ),
    ]
)
