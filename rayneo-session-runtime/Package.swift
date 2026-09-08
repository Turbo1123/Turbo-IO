// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RayNeoSessionRuntime",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "RayNeoSessionRuntime", targets: ["RayNeoSessionRuntime"]),
        .library(name: "RayNeoSessionRuntimeTestSupport", targets: ["RayNeoSessionRuntimeTestSupport"]),
        .executable(name: "rayneo-session-demo", targets: ["RayNeoSessionRuntimeDemo"])
    ],
    dependencies: [.package(path: "../rayneo-session")],
    targets: [
        .target(name: "RayNeoSessionRuntime", dependencies: [.product(name: "RayNeoSession", package: "rayneo-session")]),
        .target(name: "RayNeoSessionRuntimeTestSupport", dependencies: ["RayNeoSessionRuntime"]),
        .executableTarget(name: "RayNeoSessionRuntimeDemo", dependencies: ["RayNeoSessionRuntime", "RayNeoSessionRuntimeTestSupport"]),
        .testTarget(name: "RayNeoSessionRuntimeTests", dependencies: ["RayNeoSessionRuntime", "RayNeoSessionRuntimeTestSupport"])
    ]
)
