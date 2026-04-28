// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GalleyKit",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "GalleyCoreKit", targets: ["GalleyCoreKit"]),
    .library(name: "GalleyServerKit", targets: ["GalleyServerKit"])
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
      name: "GalleyCoreKit",
      dependencies: [
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "ALFoundation", package: "swift-core-kit")
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .target(
      name: "GalleyServerKit",
      dependencies: [
        "GalleyCoreKit",
        .product(name: "FlyingFox", package: "FlyingFox"),
        .product(name: "FlyingSocks", package: "FlyingFox")
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "GalleyCoreKitTests",
      dependencies: ["GalleyCoreKit"]
    ),
    .testTarget(
      name: "GalleyServerKitTests",
      dependencies: ["GalleyServerKit"]
    )
  ]
)
