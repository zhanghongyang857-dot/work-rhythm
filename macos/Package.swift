// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkRhythmV0",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WorkRhythmV0", targets: ["WorkRhythmV0"]),
        .executable(name: "TimerCoreCheck", targets: ["TimerCoreCheck"]),
    ],
    targets: [
        .target(name: "TimerCore"),
        .executableTarget(name: "WorkRhythmV0", dependencies: ["TimerCore"]),
        .executableTarget(name: "TimerCoreCheck", dependencies: ["TimerCore"]),
    ],
)
