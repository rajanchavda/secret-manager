// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sec",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "sec",
            targets: ["sec"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "sec",
            dependencies: [],
            path: "Sources/sec"
        ),
        .testTarget(
            name: "secTests",
            dependencies: ["sec"],
            path: "Tests/secTests"
        )
    ]
)
