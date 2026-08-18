// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ConvertAnything",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ConvertAnythingCore", targets: ["ConvertAnythingCore"]),
    .library(name: "ConvertAnythingMac", targets: ["ConvertAnythingMac"]),
    .executable(name: "ConvertAnythingApp", targets: ["ConvertAnythingApp"]),
  ],
  targets: [
    .target(name: "ConvertAnythingCore"),
    .target(name: "ConvertAnythingMac", dependencies: ["ConvertAnythingCore"]),
    .executableTarget(name: "ConvertAnythingApp", dependencies: ["ConvertAnythingMac"]),
    .executableTarget(
      name: "ConvertAnythingCoreTests",
      dependencies: ["ConvertAnythingCore"],
      path: "Tests/ConvertAnythingCoreTests"
    ),
    .executableTarget(
      name: "ConvertAnythingMacTests",
      dependencies: ["ConvertAnythingMac"],
      path: "Tests/ConvertAnythingMacTests"
    ),
    .executableTarget(
      name: "ConvertAnythingIntegrationTests",
      dependencies: ["ConvertAnythingCore"],
      path: "Tests/ConvertAnythingIntegrationTests"
    ),
  ]
)
