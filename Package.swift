// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TreadmillBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TreadmillBar", path: "Sources/TreadmillBar"),
    ]
)
