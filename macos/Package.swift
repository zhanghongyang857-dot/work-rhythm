// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkRhythmV0",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WorkRhythmV0", targets: ["WorkRhythmV0"]),
    ],
    targets: [
        .executableTarget(name: "WorkRhythmV0"),
    ],
)
