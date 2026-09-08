// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RayNeoAudioContainer",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "RayNeoAudioContainer", targets: ["RayNeoAudioContainer"])],
    targets: [
        .target(name: "RayNeoAudioContainer"),
        .testTarget(name: "RayNeoAudioContainerTests", dependencies: ["RayNeoAudioContainer"])
    ]
)
