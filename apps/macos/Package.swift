// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AgentBurn",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "AgentBurn", targets: ["AgentBurn"])],
  dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
  targets: [
    .executableTarget(
      name: "AgentBurn", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
      resources: [.copy("Resources/MenuBarIcon.pdf"), .copy("Resources/Brands")]),
    .testTarget(name: "AgentBurnTests", dependencies: ["AgentBurn"]),
  ]
)
