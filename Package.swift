// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hexbound",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Hexbound",
            path: "Sources/Hexbound"
        )
    ]
)
