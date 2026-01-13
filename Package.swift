// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftLibSSH",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(
      name: "SwiftLibSSH",
      targets: ["SwiftLibSSH"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.2.0")
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
        .product(name: "Crypto", package: "swift-crypto"),
      ],
    ),
  ]
)
