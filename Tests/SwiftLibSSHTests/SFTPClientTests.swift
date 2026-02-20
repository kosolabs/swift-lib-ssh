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
  struct Attributes {
    @Test func attributesSucceeds() async throws {
      try await withAuthenticatedClient { ssh in
        let path = "/tmp/stat-test.dat"
        try await ssh.execute("dd if=/dev/urandom of=\(path) bs=1024 count=1")

        let attrs = try await ssh.withSftp { sftp in
          try await sftp.attributes(atPath: path)
        }

        #expect(attrs.name == nil)
        #expect(attrs.type == .regular)
        #expect(attrs.size == 1024)
      }
    }

    @Test func attributesOfMissingFileThrowsNoSuchFile() async throws {
      await #expect {
        try await withAuthenticatedClient { ssh in
          try await ssh.withSftp { sftp in
            try await sftp.attributes(atPath: "/tmp/missing.dat")
          }
        }
      } throws: { error in
        (error as? SSHError)?.sftpError == .noSuchFile
      }
    }
  }

  struct SetPermissions {
    @Test func setPermissionsSucceeds() async throws {
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
  }

  struct CreateDirectory {
    @Test func createDirectorySucceeds() async throws {
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

    @Test func createExistingDirectoryThrowsFileAlreadyExists() async throws {
      await #expect {
        try await withAuthenticatedClient { ssh in
          let path = "/tmp/test-create-existing-directory"
          try await ssh.execute("rm -rf \(path) && mkdir \(path)")

          try await ssh.withSftp(perform: { sftp in
            try await sftp.createDirectory(atPath: path)
          })
        }
      } throws: { error in
        (error as? SSHError)?.sftpError == .fileAlreadyExists
      }
    }
  }

  struct RemoveDirectory {
    @Test func removeDirectorySucceeds() async throws {
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

    @Test func removeMissingDirectoryThrowsNoSuchFile() async throws {
      await #expect {
        try await withAuthenticatedClient { ssh in
          try await ssh.withSftp(perform: { sftp in
            try await sftp.removeDirectory(atPath: "/tmp/missing")
          })
        }
      } throws: { error in
        (error as? SSHError)?.sftpError == .noSuchFile
      }
    }
  }

  struct IterateDirectory {
    @Test func iterateDirectorySucceeds() async throws {
      try await withAuthenticatedClient { ssh in
        let dirPath = "/tmp/test-iterate-directory"
        try await ssh.execute("rm -rf \(dirPath) && mkdir \(dirPath)")

        try await ssh.execute("touch \(dirPath)/file{1..3}.txt")

        try await ssh.withSftp(perform: { sftp in
          let names = try await sftp.withDirectory(atPath: dirPath) { directory in
            var names = Set<String>()
            for try await attrs in directory {
              if let name = attrs.name {
                names.insert(name)
              }
            }
            return names
          }

          #expect(names == Set(["file1.txt", "file2.txt", "file3.txt"]))
        })
      }
    }

    @Test func iterateMissingDirectoryThrowsNoSuchFile() async throws {
      await #expect {
        try await withAuthenticatedClient { ssh in
          try await ssh.withSftp(perform: { sftp in
            try await sftp.withDirectory(atPath: "/tmp/missing") { directory in
              for try await _ in directory {}
            }
          })
        }
      } throws: { error in
        (error as? SSHError)?.sftpError == .noSuchFile
      }
    }
  }

  struct Limits {
    @Test func limitsSucceeds() async throws {
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
  }

  struct Download {
    @Test func downloadSucceeds() async throws {
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
  }

  struct Upload {
    @Test func testUploadSucceeds() async throws {
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

  @Test func testRenameFileSucceeds() async throws {
    try await withAuthenticatedClient { ssh in
      let oldPath = "/tmp/test-rename-old.txt"
      let newPath = "/tmp/test-rename-new.txt"

      try await ssh.execute("touch \(oldPath) && rm -f \(newPath)")

      try await ssh.withSftp { sftp in
        try await sftp.move(from: oldPath, to: newPath)
      }

      let oldAttrs = try await ssh.withSftp { sftp in
        try? await sftp.attributes(atPath: oldPath)
      }
      #expect(oldAttrs == nil)

      let newAttrs = try await ssh.withSftp { sftp in
        try await sftp.attributes(atPath: newPath)
      }
      #expect(newAttrs.type == .regular)
    }
  }

  @Test func testRenameMissingFileThrowsNoSuchFile() async throws {
    await #expect {
      try await withAuthenticatedClient { ssh in
        try await ssh.withSftp { sftp in
          try await sftp.move(from: "/tmp/missing.dat", to: "/tmp/new.dat")
        }
      }
    } throws: { error in
      (error as? SSHError)?.sftpError == .noSuchFile
    }
  }

  @Test func testMoveFileSucceeds() async throws {
    try await withAuthenticatedClient { ssh in
      let oldFolder = "/tmp/test-move-old"
      let newFolder = "/tmp/test-move-new"
      let oldPath = "\(oldFolder)/file.txt"
      let newPath = "\(newFolder)/file.txt"

      try await ssh.execute("rm -rf \(oldFolder) \(newFolder)")
      try await ssh.execute("mkdir \(oldFolder) && mkdir \(newFolder) && touch \(oldPath)")

      try await ssh.withSftp { sftp in
        try await sftp.move(from: oldPath, to: newPath)
      }

      let oldAttrs = try await ssh.withSftp { sftp in
        try? await sftp.attributes(atPath: oldPath)
      }
      #expect(oldAttrs == nil)

      let newAttrs = try await ssh.withSftp { sftp in
        try await sftp.attributes(atPath: newPath)
      }
      #expect(newAttrs.type == .regular)
    }
  }

  struct RemoveFile {
    @Test func removeFileSucceeds() async throws {
      try await withAuthenticatedClient { ssh in
        let path = "/tmp/test-remove-file.txt"
        try await ssh.execute("touch \(path)")

        try await ssh.withSftp { sftp in
          try await sftp.removeFile(atPath: path)
        }

        let attrs = try await ssh.withSftp { sftp in
          try? await sftp.attributes(atPath: path)
        }

        #expect(attrs == nil)
      }
    }

    @Test func removeMissingFileThrowsNoSuchFile() async throws {
      await #expect {
        try await withAuthenticatedClient { ssh in
          try await ssh.withSftp { sftp in
            try await sftp.removeFile(atPath: "/tmp/missing.dat")
          }
        }
      } throws: { error in
        (error as? SSHError)?.sftpError == .noSuchFile
      }
    }
  }
}
