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
        .executableTarget(
            name: "Foundry",
            path: "Sources/Foundry",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "FoundryTests",
            dependencies: ["Foundry"],
            path: "Tests/FoundryTests"
        )
    ]
)
