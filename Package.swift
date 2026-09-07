// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LumaDesk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LumaDesk", targets: ["LumaDesk"]), .executable(name: "LumaDeskChecks", targets: ["LumaDeskChecks"]), .library(name: "LumaCore", targets: ["LumaCore"])],
    targets: [
        .target(name: "LumaCore"),
        .target(name: "LumaServices", dependencies: ["LumaCore"]),
        .executableTarget(name: "LumaDesk", dependencies: ["LumaCore", "LumaServices"]),
        .target(name: "LumaValidation", dependencies: ["LumaCore", "LumaServices"], path: "Tests/LumaValidation"),
        .executableTarget(name: "LumaDeskChecks", dependencies: ["LumaValidation"]),
        .testTarget(name: "LumaCoreTests", dependencies: ["LumaValidation"])
    ]
)
