// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Foundry",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Foundry", targets: ["Foundry"])
    ],
    targets: [
        .target(
            name: "FoundryDomain",
            path: "Sources/FoundryDomain"
        ),
        .target(
            name: "FoundryServices",
            dependencies: ["FoundryDomain"],
            path: "Sources/FoundryServices"
        ),
        .executableTarget(
            name: "Foundry",
            dependencies: ["FoundryDomain", "FoundryServices"],
            path: "Sources/Foundry",
            resources: [
                .copy("Resources/ProviderIcons/anthropic.svg"),
                .copy("Resources/ProviderIcons/opencode.svg"),
                .copy("Resources/FirefoxConnector/manifest.json"),
                .copy("Resources/FirefoxConnector/background.js"),
                .copy("Resources/BackgroundRemoval/NOTICE.txt"),
                .copy("Resources/BackgroundRemoval/background_removal_worker.py"),
                .copy("Resources/emoji.tsv")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "FoundryTests",
            dependencies: ["Foundry", "FoundryDomain", "FoundryServices"],
            path: "Tests/FoundryTests"
        )
    ]
)
