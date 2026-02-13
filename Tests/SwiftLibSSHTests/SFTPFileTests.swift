import Foundation
import Testing

@testable import SwiftLibSSH

struct SFTPFileTests {
  @Test func testAttributes() async throws {
    try await withAuthenticatedClient { ssh in
      let path = "/tmp/stat-file-test.dat"
      try await ssh.execute("dd if=/dev/urandom of=\(path) bs=1024 count=1")

      let attrs = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: path, accessType: .readOnly) { file in
          try await file.attributes()
        }
      }

      #expect(attrs.name == nil)
      #expect(attrs.type == .regular)
      #expect(attrs.size == 1024)
    }
  }

  @Test func testReadSmall() async throws {
    try await withAuthenticatedClient { ssh in
      let srcPath = "/tmp/read-small-test.dat"

      try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1024 count=1")
      let expected = try await ssh.md5(ofFile: srcPath)

      let actual = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
          try await file.read().md5()
        }
      }

      #expect(actual == expected)
    }
  }

  @Test func testReadSome() async throws {
    try await withAuthenticatedClient { ssh in
      let srcPath = "/tmp/read-some-test.dat"
      let offset = 153600 as UInt64
      let length = 153600 as UInt64

      try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1M count=1")
      let expected = try await ssh.md5(ofFile: srcPath, offset: offset, length: length)

      let actual = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
          try await file.read(offset: offset, length: length).md5()
        }
      }

      #expect(actual == expected)
    }
  }

  @Test func testReadBig() async throws {
    try await withAuthenticatedClient { ssh in
      let srcPath = "/tmp/read-big-test.dat"

      try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1M count=1")
      let expected = try await ssh.md5(ofFile: srcPath)

      let actual = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
          try await file.read().md5()
        }
      }

      #expect(actual == expected)
    }
  }

  @Test func testStreamSmall() async throws {
    try await withAuthenticatedClient { ssh in
      let srcPath = "/tmp/stream-small-test.dat"

      try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1024 count=1")
      let expected = try await ssh.md5(ofFile: srcPath)

      let actual = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
          var result = Data()
          for try await data in file.stream(length: 1024) {
            result.append(data)
          }
          return result.md5()
        }
      }

      #expect(actual == expected)
    }
  }

  @Test func testStreamSome() async throws {
    try await withAuthenticatedClient { ssh in
      let srcPath = "/tmp/stream-some-test.dat"
      let offset = 153600 as UInt64
      let length = 153600 as UInt64

      try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1M count=1")
      let expected = try await ssh.md5(ofFile: srcPath, offset: offset, length: length)

      let actual = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
          var result = Data()
          for try await data in file.stream(offset: offset, length: length) {
            result.append(data)
          }
          return result.md5()
        }
      }

      #expect(actual == expected)
    }
  }

  @Test func testStreamBig() async throws {
    try await withAuthenticatedClient { ssh in
      let srcPath = "/tmp/stream-big-test.dat"

      try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1M count=1")
      let expected = try await ssh.md5(ofFile: srcPath)

      let actual = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
          var result = Data()
          for try await data in file.stream(length: 1_048_576) {
            result.append(data)
          }
          return result.md5()
        }
      }

      #expect(actual == expected)
    }
  }

  @Test func testCancellationOfForAwaitLoopOverSftpStream() async throws {
    try await withAuthenticatedClient { ssh in
      try await ssh.execute("dd if=/dev/urandom of=/tmp/drain.dat bs=1M count=1")

      let expected = try await ssh.withSftp { sftp in
        try await sftp.attributes(atPath: "/tmp/drain.dat").size
      }

      let actual = try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: "/tmp/drain.dat", accessType: .readOnly) { file in
          for try await data in file.stream() {
            // Returning here causes stream to cancel
            return data
          }
          fatalError("Stream should not complete")
        }
      }

      #expect(actual.count > 0)
      #expect(actual.count < expected)
    }
  }

  @Test func testWriteSmall() async throws {
    try await withAuthenticatedClient { ssh in
      let destPath = "/tmp/write-small-test.dat"

      let data =
        Data((0..<1024).map { _ in UInt8.random(in: .min ... .max) })
      let expected = data.md5()

      try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: destPath, accessType: .writeOnly, mode: 0o644) { file in
          try await file.write(data: data)
        }
      }

      let actual = try await ssh.md5(ofFile: destPath)

      #expect(actual == expected)
    }
  }

  @Test func testWriteBig() async throws {
    try await withAuthenticatedClient { ssh in
      let destPath = "/tmp/write-big-test.dat"

      let data =
        Data((0..<1_048_576).map { _ in UInt8.random(in: .min ... .max) })
      let expected = data.md5()

      try await ssh.withSftp { sftp in
        try await sftp.withSftpFile(atPath: destPath, accessType: .writeOnly, mode: 0o644) { file in
          try await file.write(data: data)
        }
      }

      let actual = try await ssh.md5(ofFile: destPath)

      #expect(actual == expected)
    }
  }

  @Test func testSimultaneousDownload() async throws {
    try await withAuthenticatedClient { ssh in
      let path1 = "/tmp/simultaneous-1-test.dat"
      let path2 = "/tmp/simultaneous-2-test.dat"

      // Create two large files
      try await ssh.execute("dd if=/dev/urandom of=\(path1) bs=1M count=5")
      try await ssh.execute("dd if=/dev/urandom of=\(path2) bs=1M count=5")

      let expected1 = try await ssh.md5(ofFile: path1)
      let expected2 = try await ssh.md5(ofFile: path2)

      try await ssh.withSftp { sftp in
        async let md5_1 = sftp.withSftpFile(atPath: path1, accessType: .readOnly) { file in
          try await file.read().md5()
        }
        async let md5_2 = sftp.withSftpFile(atPath: path2, accessType: .readOnly) { file in
          try await file.read().md5()
        }

        let (actual1, actual2) = try await (md5_1, md5_2)

        #expect(actual1 == expected1)
        #expect(actual2 == expected2)
      }
    }
  }
}
