// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "OptimizeAnything",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "OptimizeAnythingCore", targets: ["OptimizeAnythingCore"])
  ],
  targets: [
    .target(name: "OptimizeAnythingCore"),
    .executableTarget(
      name: "OptimizeAnythingCoreTests",
      dependencies: ["OptimizeAnythingCore"],
      path: "Tests/OptimizeAnythingCoreTests"
    ),
  ]
)
