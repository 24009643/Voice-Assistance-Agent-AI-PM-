// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParaformerProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ParaformerProbe"),
        .testTarget(name: "ParaformerProbeTests", dependencies: ["ParaformerProbe"])
    ]
)
