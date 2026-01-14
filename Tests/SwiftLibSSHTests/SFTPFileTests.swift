import Crypto
import Foundation
import Synchronization
import Testing

@testable import SwiftLibSSH

@discardableResult
func shell(_ command: String) throws -> (status: Int32, stdout: Data, stderr: Data) {
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
    process.terminationStatus,
    stdout.fileHandleForReading.readDataToEndOfFile(),
    stderr.fileHandleForReading.readDataToEndOfFile()
  )
}

func md5(
  ofFile path: String, offset: UInt64 = 0, length: UInt64 = UInt64(UInt32.max)
) throws -> String {
  let command = "tail -c +\(offset + 1) \(path) | head -c \(length) | md5sum"
  return try shell(command)
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
  func md5(
    ofFile path: String, offset: UInt64 = 0, length: UInt64 = UInt64(UInt32.max)
  ) async throws -> String {
    let command = "tail -c +\(offset + 1) \(path) | head -c \(length) | md5sum"
    return try await self.execute(command)
      .stdout
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

    try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1M count=1")
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

    try await ssh.execute("dd if=/dev/urandom of=\(srcPath) bs=1M count=1")
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

    await ssh.close()
  }

  @Test func testStreamBig() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

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

    await ssh.close()
  }

  @Test func testCancellationOfForAwaitLoopOverSftpStream() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

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
        throw TestError.noData
      }
    }

    #expect(actual.count > 0)
    #expect(actual.count < expected)

    await ssh.close()
  }

  @Test func testWriteSmall() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

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

    await ssh.close()
  }

  @Test func testWriteBig() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

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

    await ssh.close()
  }
}
