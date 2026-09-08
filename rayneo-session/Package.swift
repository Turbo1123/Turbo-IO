// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RayNeoSession",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "RayNeoSession", targets: ["RayNeoSession"]),
        .executable(name: "rayneo-approval-demo", targets: ["RayNeoApprovalDemo"])
    ],
    targets: [
        .target(name: "RayNeoSession"),
        .executableTarget(name: "RayNeoApprovalDemo", dependencies: ["RayNeoSession"]),
        .testTarget(name: "RayNeoSessionTests", dependencies: ["RayNeoSession"])
    ]
)
