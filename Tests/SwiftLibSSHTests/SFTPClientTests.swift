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

  @Test func testDownload() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let destURL = FileManager
      .default
      .temporaryDirectory
      .appendingPathComponent("rand.dat")

    try await ssh.execute("dd if=/dev/urandom of=/tmp/rand.dat bs=1047552 count=5")
    let expected = try await ssh.execute("md5sum /tmp/rand.dat | cut -d' ' -f1")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    try await ssh.withSftp(perform: { sftp in
      let size = try await sftp.stat(atPath: "/tmp/rand.dat").size
      let transferred = Atomic<UInt64>(0)

      try await sftp.download(from: "/tmp/rand.dat", to: destURL) { progress in
        transferred.store(progress, ordering: .relaxed)
      }
      #expect(transferred.load(ordering: .relaxed) == size)
    })

    let actual = try shell("md5sum \(destURL.path) | cut -d' ' -f1")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(actual == expected)

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
