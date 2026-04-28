// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GalleyKit",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GalleyKit", targets: ["GalleyKit"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/swhitty/FlyingFox.git",
      from: "0.26.2"),
    .package(
      url: "https://github.com/swiftlang/swift-markdown",
      from: "0.7.3"),
    .package(
      url: "https://github.com/leuski/swift-core-kit.git",
      branch: "main")
  ],
  targets: [
    .target(
      name: "GalleyKit",
      dependencies: [
        .product(name: "FlyingFox", package: "FlyingFox"),
        .product(name: "FlyingSocks", package: "FlyingFox"),
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "ALFoundation", package: "swift-core-kit")
      ]
    ),
    .testTarget(
      name: "GalleyKitTests",
      dependencies: ["GalleyKit"]
    )
  ]
)
