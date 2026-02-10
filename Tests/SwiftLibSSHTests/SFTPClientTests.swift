import Foundation
import Synchronization
import Testing

@testable import SwiftLibSSH

func metrics(size: UInt64, duration: Duration) -> String {
  let megabytes = Double(size) / 1_048_576
  let speed = megabytes / (duration / .seconds(1))
  return "\(megabytes)MB in \(duration): \(String(format: "%.2f", speed))MB/s"
}

struct SFTPClientTests {
  @Test func testAttributes() async throws {
    try await withAuthenticatedClient { ssh in
      let path = "/tmp/stat-test.dat"
      try await ssh.execute("dd if=/dev/urandom of=\(path) bs=1024 count=1")

      let attrs = try await ssh.withSftp { sftp in
        try await sftp.attributes(atPath: path)
      }

      // TODO: In test environment, this is null
      // #expect(attrs.name == "stat-test.dat")
      #expect(attrs.type == .regular)
      #expect(attrs.size == 1024)
    }
  }

  @Test func testSetPermissions() async throws {
    try await withAuthenticatedClient { ssh in
      // Prepare a temp file
      try await ssh.execute("rm -f /tmp/sftp-perm.txt && touch /tmp/sftp-perm.txt")

      try await ssh.withSftp(perform: { sftp in
        let before = try await sftp.attributes(atPath: "/tmp/sftp-perm.txt")
        #expect((before.permissions & 0o777) != 0x644)

        try await sftp.setPermissions(atPath: "/tmp/sftp-perm.txt", mode: 0o644)
        let after = try await sftp.attributes(atPath: "/tmp/sftp-perm.txt")
        #expect((after.permissions & 0o777) == 0o644)
      })
    }
  }

  @Test func testCreateDirectory() async throws {
    try await withAuthenticatedClient { ssh in
      let path = "/tmp/test-create-directory"
      try await ssh.execute("rmdir \(path)")

      try await ssh.withSftp(perform: { sftp in
        try await sftp.createDirectory(atPath: path)
      })

      let attrs = try await ssh.withSftp(perform: { sftp in
        try await sftp.attributes(atPath: path)
      })

      #expect(attrs.type == .directory)
    }
  }

  @Test func testRemoveDirectory() async throws {
    try await withAuthenticatedClient { ssh in
      let path = "/tmp/test-remove-directory"
      try await ssh.execute("mkdir \(path)")

      try await ssh.withSftp(perform: { sftp in
        try await sftp.removeDirectory(atPath: path)
      })

      let attrs = try await ssh.withSftp(perform: { sftp in
        try? await sftp.attributes(atPath: path)
      })

      #expect(attrs == nil)
    }
  }

  @Test func testIterateDirectory() async throws {
    try await withAuthenticatedClient { ssh in
      let dirPath = "/tmp/test-iterate-directory"
      try await ssh.execute("rm -rf \(dirPath) && mkdir \(dirPath)")

      try await ssh.execute("touch \(dirPath)/file{1..3}.txt")

      try await ssh.withSftp(perform: { sftp in
        let names = try await sftp.withDirectory(atPath: dirPath) { directory in
          var names = Set<String>()
          for try await attrs in directory {
            names.insert(attrs.name)
          }
          return names
        }

        #expect(names == Set(["file1.txt", "file2.txt", "file3.txt"]))
      })
    }
  }

  @Test func testLimits() async throws {
    try await withAuthenticatedClient { ssh in
      try await ssh.withSftp(perform: { sftp in
        let limits = try await sftp.limits()
        #expect(limits.maxOpenHandles > 0)
        #expect(limits.maxPacketLength > 0)
        #expect(limits.maxReadLength > 0)
        #expect(limits.maxWriteLength > 0)
      })
    }
  }

  @Test func testDownload() async throws {
    try await withAuthenticatedClient { ssh in
      let srcPath = "/tmp/dl-test.dat"

      let destURL = FileManager
        .default
        .temporaryDirectory
        .appendingPathComponent("dl-test.dat")

      try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1M count=50")
      let expected = try await ssh.md5(ofFile: srcPath)

      try await ssh.withSftp { sftp in
        let attrs = try await sftp.attributes(atPath: srcPath)
        let transferred = Atomic<UInt64>(0)

        let elapsed = try await ContinuousClock().measure {
          try await sftp.download(from: srcPath, to: destURL) { progress in
            transferred.store(progress, ordering: .relaxed)
          }
        }
        print("Download: \(metrics(size: attrs.size, duration: elapsed))")

        #expect(transferred.load(ordering: .relaxed) == attrs.size)
      }

      let actual = try md5(ofFile: destURL.path)
      #expect(actual == expected)
    }
  }

  @Test func testUpload() async throws {
    try await withAuthenticatedClient { ssh in
      let srcURL = FileManager
        .default
        .temporaryDirectory
        .appendingPathComponent("ul-test.dat")

      let destPath = "/tmp/ul-test.dat"

      try shell("dd if=/dev/urandom of=\(srcURL.path) bs=1M count=50")
      let expected = try md5(ofFile: srcURL.path)

      try await ssh.withSftp { sftp in
        let size = try FileManager.default.attributesOfItem(atPath: srcURL.path)[.size] as! UInt64
        let transferred = Atomic<UInt64>(0)

        let elapsed = try await ContinuousClock().measure {
          try await sftp.upload(from: srcURL, to: destPath, mode: 0o644) { progress in
            transferred.store(progress, ordering: .relaxed)
          }
        }
        print("Upload: \(metrics(size: size, duration: elapsed))")

        #expect(transferred.load(ordering: .relaxed) == size)
      }

      try await Task.sleep(for: .seconds(1))
      let actual = try await ssh.md5(ofFile: destPath)
      #expect(actual == expected)
    }
  }
}
