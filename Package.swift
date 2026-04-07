// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeStat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeStat",
            path: "Sources/ClaudeStat"
        )
    ]
)
