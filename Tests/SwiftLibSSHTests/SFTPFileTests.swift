import Crypto
import Foundation
import Synchronization
import Testing

@testable import SwiftLibSSH

@discardableResult
func shell(_ command: String) throws -> (stdout: Data, stderr: Data) {
  let process = Process()
  let stdout = Pipe()
  let stderr = Pipe()

  process.standardOutput = stdout
  process.standardError = stderr
  process.executableURL = URL(fileURLWithPath: "/bin/bash")
  process.arguments = ["-c", command]

  try process.run()
  process.waitUntilExit()

  return (
    stdout.fileHandleForReading.readDataToEndOfFile(),
    stderr.fileHandleForReading.readDataToEndOfFile()
  )
}

func md5(ofFile url: URL, offset: UInt64 = 0, length: UInt64? = nil) throws -> String {
  let countArg = length.map { "count=\($0)" } ?? ""
  return try shell("dd if=\(url.path) bs=1 skip=\(offset) \(countArg) | md5sum")
    .stdout
    .decoded(as: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .split(separator: " ")[0]
    .lowercased()
}

extension Data {
  func md5() -> String {
    let digest = Insecure.MD5.hash(data: self)
    return digest.map { String(format: "%02hhx", $0) }.joined()
  }
}

extension SSHClient {
  func md5(ofFile path: String, offset: UInt64 = 0, length: UInt64? = nil) async throws -> String {
    let countArg = length.map { "count=\($0)" } ?? ""
    return try await self.execute("dd if=\(path) bs=1 skip=\(offset) \(countArg) | md5sum")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: " ")[0]
      .lowercased()
  }
}

struct SFTPFileTests {
  @Test func testReadSmall() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let srcPath = "/tmp/read-small-test.dat"

    try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1024 count=1")
    let expected = try await ssh.md5(ofFile: srcPath)

    let actual = try await ssh.withSftp { sftp in
      try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
        try await file.read().md5()
      }
    }

    #expect(actual == expected)

    await ssh.close()
  }

  @Test func testReadSome() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let srcPath = "/tmp/read-some-test.dat"
    let offset = 153600 as UInt64
    let length = 153600 as UInt64

    try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1048576 count=1")
    let expected = try await ssh.md5(ofFile: srcPath, offset: offset, length: length)

    let actual = try await ssh.withSftp { sftp in
      try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
        try await file.read(offset: offset, length: length).md5()
      }
    }

    #expect(actual == expected)

    await ssh.close()
  }

  @Test func testReadBig() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let srcPath = "/tmp/read-big-test.dat"

    try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1048576 count=1")
    let expected = try await ssh.md5(ofFile: srcPath)

    let actual = try await ssh.withSftp { sftp in
      try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
        try await file.read().md5()
      }
    }

    #expect(actual == expected)

    await ssh.close()
  }

  @Test func testStreamSmall() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

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

    await ssh.close()
  }

  @Test func testStreamSome() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let srcPath = "/tmp/stream-some-test.dat"
    let offset = 153600 as UInt64
    let length = 153600 as UInt64

    try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1048576 count=1")
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

    await ssh.close()
  }

  @Test func testStreamBig() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let srcPath = "/tmp/stream-big-test.dat"

    try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1048576 count=1")
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

    await ssh.close()
  }

  @Test func testCancellationOfForAwaitLoopOverSftpStream() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    try await ssh.execute("dd if=/dev/urandom of=/tmp/drain.dat bs=1047552 count=1")

    let expected = try await ssh.withSftp { sftp in
      try await sftp.stat(atPath: "/tmp/drain.dat").size
    }

    let actual = try await ssh.withSftp { sftp in
      try await sftp.withSftpFile(atPath: "/tmp/drain.dat", accessType: .readOnly) { file in
        for try await data in file.stream() {
          // Returning here causes stream to cancel
          return data
        }
        throw TestError.noData
      }
    }

    #expect(actual.count > 0)
    #expect(actual.count < expected)

    await ssh.close()
  }

  @Test func testStatAndSetPermissions() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    // Prepare a temp file
    try await ssh.execute("rm -f /tmp/sftp-perm.txt && touch /tmp/sftp-perm.txt")

    try await ssh.withSftp(perform: { sftp in
      let before = try await sftp.stat(atPath: "/tmp/sftp-perm.txt")
      #expect((before.permissions & 0o777) != 0x644)

      try await sftp.setPermissions(atPath: "/tmp/sftp-perm.txt", mode: 0o644)
      let after = try await sftp.stat(atPath: "/tmp/sftp-perm.txt")
      #expect((after.permissions & 0o777) == 0o644)
    })

    await ssh.close()
  }
}
