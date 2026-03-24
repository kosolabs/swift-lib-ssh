// swift-tools-version: 6.1
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
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1")
  ],
  targets: [
    .target(
      name: "CLibSSH",
      path: "Sources/CLibSSH",
      publicHeadersPath: "include",
      cSettings: [
        .headerSearchPath("include")
      ],
      linkerSettings: [
        .unsafeFlags([
          "-L\(Context.packageDirectory)/Sources/CLibSSH/lib",
          "-lssh",
          "-lssl",
          "-lcrypto",
        ])
      ]
    ),
    .target(
      name: "SwiftLibSSH",
      dependencies: ["CLibSSH"]
    ),
    .executableTarget(
      name: "SwiftSSH",
      dependencies: [
        "SwiftLibSSH",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "SwiftLibSSHTests",
      dependencies: ["SwiftLibSSH"],
    ),
  ]
)
