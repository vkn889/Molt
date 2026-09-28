// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Molt", platforms: [.macOS(.v13)], products: [.executable(name: "Molt", targets: ["Molt"])],
  targets: [
    .target(name: "MoltCore"),
    .executableTarget(name: "Molt", dependencies: ["MoltCore"], resources: [.copy("Resources")]),
    .testTarget(name: "MoltCoreTests", dependencies: ["MoltCore"]),
  ])
