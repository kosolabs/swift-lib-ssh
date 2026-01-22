// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftLibSSH",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(
      name: "SwiftLibSSH",
      targets: ["SwiftLibSSH"]
    )
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
    .testTarget(
      name: "SwiftLibSSHTests",
      dependencies: ["SwiftLibSSH"],
    ),
  ]
)
