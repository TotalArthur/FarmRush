// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FarmRush",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FarmRush",
            path: "Sources/FarmRush"
        )
    ]
)
