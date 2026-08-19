// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SenseVoiceProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx", exact: "1.13.6")
    ],
    targets: [
        .executableTarget(
            name: "SenseVoiceProbe",
            dependencies: [.product(name: "sherpa-onnx", package: "sherpa-onnx")]
        ),
        .testTarget(name: "SenseVoiceProbeTests", dependencies: ["SenseVoiceProbe"])
    ]
)
