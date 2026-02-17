// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hlopya",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hlopya", targets: ["Hlopya"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Hlopya",
            dependencies: ["FluidAudio", "Yams"],
            path: "Hlopya",
            exclude: ["Info.plist", "Hlopya.entitlements", "Assets.xcassets"]
        ),
    ]
)
