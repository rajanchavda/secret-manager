// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sec",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "sec",
            targets: ["sec"]
        ),
        .executable(
            name: "SecApp",
            targets: ["SecApp"]
        ),
        .library(
            name: "SecCore",
            targets: ["SecCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SecCore",
            dependencies: [],
            path: "Sources/SecCore"
        ),
        .executableTarget(
            name: "sec",
            dependencies: ["SecCore"],
            path: "Sources/sec"
        ),
        .executableTarget(
            name: "SecApp",
            dependencies: ["SecCore"],
            path: "Sources/SecApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "secTests",
            dependencies: ["SecCore", "sec"],
            path: "Tests/secTests"
        )
    ]
)
