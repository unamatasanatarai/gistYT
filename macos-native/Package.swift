// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "gistYT",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "gistYT",
            targets: ["gistYT"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "gistYT",
            dependencies: [],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["gistYT"],
            path: "Tests/AppTests"
        )
    ]
)
