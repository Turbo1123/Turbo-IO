// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RayNeoDisplay",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "RayNeoDisplay", targets: ["RayNeoDisplay"]),
        .executable(name: "rayneo-display-demo", targets: ["RayNeoDisplayDemo"])
    ],
    targets: [
        .target(name: "RayNeoDisplay"),
        .executableTarget(name: "RayNeoDisplayDemo", dependencies: ["RayNeoDisplay"]),
        .testTarget(name: "RayNeoDisplayTests", dependencies: ["RayNeoDisplay"])
    ]
)
