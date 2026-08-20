// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkRhythmV0",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WorkRhythmV0", targets: ["WorkRhythmV0"]),
        .executable(name: "TimerCoreCheck", targets: ["TimerCoreCheck"]),
        .executable(name: "FocusDataCoreCheck", targets: ["FocusDataCoreCheck"]),
    ],
    targets: [
        .target(name: "TimerCore"),
        .target(name: "FocusDataCore"),
        .executableTarget(name: "WorkRhythmV0", dependencies: ["TimerCore", "FocusDataCore"]),
        .executableTarget(name: "TimerCoreCheck", dependencies: ["TimerCore"]),
        .executableTarget(name: "FocusDataCoreCheck", dependencies: ["FocusDataCore"]),
    ],
)
