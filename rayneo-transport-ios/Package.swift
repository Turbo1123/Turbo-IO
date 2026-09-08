// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RayNeoTransportIOS",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "RayNeoTransportCore", targets: ["RayNeoTransportCore"]),
        .library(name: "RayNeoTransportIOS", targets: ["RayNeoTransportIOS"])
    ],
    targets: [
        .target(name: "RayNeoTransportCore"),
        .target(name: "RayNeoTransportIOS", dependencies: ["RayNeoTransportCore"]),
        .testTarget(name: "RayNeoTransportCoreTests", dependencies: ["RayNeoTransportCore"])
    ]
)
