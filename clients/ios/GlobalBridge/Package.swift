// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GlobalBridge",
    platforms: [
        .iOS(.v17),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "GlobalBridge",
            targets: ["GlobalBridge"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/davidstump/SwiftPhoenixClient", from: "5.3.5"),
        .package(url: "https://github.com/auth0/Auth0.swift", from: "2.15.1"),
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.4"),
    ],
    targets: [
        .target(
            name: "GlobalBridge",
            dependencies: [
                .product(name: "SwiftPhoenixClient", package: "SwiftPhoenixClient"),
                .product(name: "Auth0", package: "Auth0.swift"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: ".",
            exclude: [
                "Tests",
                "GlobalBridgeTests",
                "Documentation",
                "Examples",
                "docs",
                "scripts",
                "GlobalBridge.xcodeproj"
            ],
            sources: [
                "Core",
                "Features",
                "UI",
                "GlobalBridge"
            ]
        ),
        .testTarget(
            name: "GlobalBridgeTests",
            dependencies: ["GlobalBridge"],
            path: "Tests"
        )
    ]
)
