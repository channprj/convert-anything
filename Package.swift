// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "OptimizeAnything",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "OptimizeAnythingCore", targets: ["OptimizeAnythingCore"]),
    .library(name: "OptimizeAnythingMac", targets: ["OptimizeAnythingMac"]),
    .executable(name: "OptimizeAnythingApp", targets: ["OptimizeAnythingApp"]),
  ],
  targets: [
    .target(name: "OptimizeAnythingCore"),
    .target(name: "OptimizeAnythingMac", dependencies: ["OptimizeAnythingCore"]),
    .executableTarget(name: "OptimizeAnythingApp", dependencies: ["OptimizeAnythingMac"]),
    .executableTarget(
      name: "OptimizeAnythingCoreTests",
      dependencies: ["OptimizeAnythingCore"],
      path: "Tests/OptimizeAnythingCoreTests"
    ),
    .executableTarget(
      name: "OptimizeAnythingMacTests",
      dependencies: ["OptimizeAnythingMac"],
      path: "Tests/OptimizeAnythingMacTests"
    ),
  ]
)
