// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "audiocap",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "audiocap",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ]
)
