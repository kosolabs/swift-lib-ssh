// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftLibSSH",
  platforms: [
    .macOS(.v10_15)
  ],
  products: [
    .library(
      name: "SwiftLibSSH",
      targets: ["SwiftLibSSH"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/angu-software/SwiftAsyncAssert.git", from: "1.1.0")
  ],
  targets: [
    .systemLibrary(
      name: "CLibSSH",
      pkgConfig: "libssh",
      providers: [
        .brew(["libssh"])
      ]
    ),
    .target(
      name: "SwiftLibSSH",
      dependencies: ["CLibSSH"]
    ),
    .testTarget(
      name: "SwiftLibSSHTests",
      dependencies: [
        "SwiftLibSSH",
        .product(name: "SwiftAsyncAssert", package: "SwiftAsyncAssert"),
      ],
      resources: [.copy("Resources")]
    ),
  ]
)
