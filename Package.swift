// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VolumeDial",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VolumeDial", targets: ["VolumeDial"])],
    targets: [
        .target(name: "DialCore"),
        .executableTarget(name: "VolumeDial", dependencies: ["DialCore"]),
        .testTarget(name: "DialCoreTests", dependencies: ["DialCore", "VolumeDial"])
    ]
)
