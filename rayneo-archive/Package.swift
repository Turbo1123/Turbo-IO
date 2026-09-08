// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RayNeoArchive",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "RayNeoArchive", targets: ["RayNeoArchive"]),
        .executable(name: "rayneo-archive-demo", targets: ["RayNeoArchiveDemo"])
    ],
    targets: [
        .target(name: "RayNeoArchive"),
        .executableTarget(name: "RayNeoArchiveDemo", dependencies: ["RayNeoArchive"]),
        .testTarget(name: "RayNeoArchiveTests", dependencies: ["RayNeoArchive"])
    ]
)
