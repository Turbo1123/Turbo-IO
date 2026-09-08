// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RayNeoProtocol",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "RayNeoProtocol", targets: ["RayNeoProtocol"])],
    targets: [
        .target(name: "RayNeoProtocol"),
        .testTarget(name: "RayNeoProtocolTests", dependencies: ["RayNeoProtocol"])
    ]
)
