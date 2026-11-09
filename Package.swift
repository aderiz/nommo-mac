// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NommoApp",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "NommoKit", targets: ["NommoKit"]),
        .library(name: "NommoUI", targets: ["NommoUI"]),
        .executable(name: "NommoApp", targets: ["NommoApp"]),
        .executable(name: "nommoctl", targets: ["nommoctl"]),
        .executable(name: "NommoSnapshot", targets: ["NommoSnapshot"]),
    ],
    targets: [
        .target(name: "NommoKit"),
        .target(name: "NommoUI", dependencies: ["NommoKit"]),
        .executableTarget(name: "NommoApp", dependencies: ["NommoUI", "NommoKit"]),
        .executableTarget(name: "nommoctl", dependencies: ["NommoKit"]),
        .executableTarget(name: "NommoSnapshot", dependencies: ["NommoUI", "NommoKit"]),
        .executableTarget(name: "screenprobe"),
        .testTarget(name: "NommoKitTests", dependencies: ["NommoKit"]),
    ]
)
