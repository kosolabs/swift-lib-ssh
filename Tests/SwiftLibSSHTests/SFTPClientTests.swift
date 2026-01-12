import Foundation
import Synchronization
import Testing

@testable import SwiftLibSSH

@discardableResult
func shell(_ command: String) throws -> Data {
  let process = Process()
  let pipe = Pipe()

  process.standardOutput = pipe
  process.standardError = pipe
  process.executableURL = URL(fileURLWithPath: "/bin/bash")
  process.arguments = ["-c", command]

  try process.run()
  process.waitUntilExit()

  return pipe.fileHandleForReading.readDataToEndOfFile()
}

struct SFTPClientTests {
  @Test func testMkdir() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    // Ensure /tmp/test-directory doesn't exist
    try await ssh.execute("rm -rf /tmp/test-directory")

    try await ssh.withSftp(perform: { sftp in
      try await sftp.makeDirectory(atPath: "/tmp/test-directory")
    })

    let after = try await ssh.execute("ls /tmp | grep -E '^test-directory$' || true")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(after == "test-directory")

    await ssh.close()
  }

  @Test func testLimits() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    try await ssh.withSftp(perform: { sftp in
      let limits = try await sftp.limits()
      #expect(limits.maxOpenHandles > 0)
      #expect(limits.maxPacketLength > 0)
      #expect(limits.maxReadLength > 0)
      #expect(limits.maxWriteLength > 0)
    })

    await ssh.close()
  }

  @Test func testRead() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let srcPath = "/tmp/readtest.dat"

    try await ssh.execute("printf '%b' \"$(printf '\\x%02x' {0..255})\" > \(srcPath)")
    let expected = Data(Array(0...255))

    let actual = try await ssh.withSftp { sftp in
      try await sftp.withSftpFile(atPath: srcPath, accessType: .readOnly) { file in
        let result = try await file.read()
        #expect(try await file.read() == nil)
        return result
      }
    }

    #expect(actual == expected)

    await ssh.close()
  }

  @Test func testDownload() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let destURL = FileManager
      .default
      .temporaryDirectory
      .appendingPathComponent("dltest.dat")

    try await ssh.execute("dd if=/dev/urandom of=/tmp/dltest.dat bs=1048576 count=1")
    let expected = try await ssh.execute("md5sum /tmp/dltest.dat | cut -d' ' -f1")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    try await ssh.withSftp { sftp in
      let size = try await sftp.stat(atPath: "/tmp/dltest.dat").size
      let transferred = Atomic<UInt64>(0)

      let elapsed = try await ContinuousClock().measure {
        try await sftp.download(from: "/tmp/dltest.dat", to: destURL) { progress in
          transferred.store(progress, ordering: .relaxed)
        }
      }
      let speed = Double(size) / 1_048_576 / (elapsed / .seconds(1))
      print("Download speed: \(String(format: "%.2f", speed))MB/s")

      #expect(transferred.load(ordering: .relaxed) == size)
    }

    let actual = try shell("md5sum \(destURL.path) | cut -d' ' -f1")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(actual == expected)

    await ssh.close()
  }

  @Test func testUpload() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let srcURL = FileManager
      .default
      .temporaryDirectory
      .appendingPathComponent("ultest.dat")

    try shell("dd if=/dev/urandom of=\(srcURL.path) bs=1048576 count=1")
    let expected = try shell("md5sum \(srcURL.path) | cut -d' ' -f1")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    try await ssh.withSftp { sftp in
      let size = try FileManager.default.attributesOfItem(atPath: srcURL.path)[.size] as! UInt64
      let transferred = Atomic<UInt64>(0)

      let elapsed = try await ContinuousClock().measure {
        try await sftp.upload(from: srcURL, to: "/tmp/ultest.dat", mode: 0o644) { progress in
          transferred.store(progress, ordering: .relaxed)
        }
      }

      let speed = Double(size) / 1_048_576 / (elapsed / .seconds(1))
      print("Upload speed: \(String(format: "%.2f", speed))MB/s")

      #expect(transferred.load(ordering: .relaxed) == size)
    }

    try await Task.sleep(for: .seconds(1))
    let actual = try await ssh.execute("md5sum /tmp/ultest.dat | cut -d' ' -f1")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
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
