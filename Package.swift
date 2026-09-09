// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "MeetingFlyby",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "MeetingFlyby",
            path: "Sources/MeetingFlyby"
        )
    ]
)
