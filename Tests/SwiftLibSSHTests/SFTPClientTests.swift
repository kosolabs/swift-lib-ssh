import Foundation
import Testing

@testable import SwiftLibSSH

struct SFTPClientTests {
  @Test func testMkdir() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    // Ensure /tmp/test-directory doesn't exist
    _ = try await ssh.execute(command: "rm -rf /tmp/test-directory")

    try await ssh.withSftp(perform: { sftp in
      try await sftp.makeDirectory(atPath: "/tmp/test-directory")
    })

    let after = try await ssh.execute(command: "ls /tmp | grep -E '^test-directory$' || true")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(after == "test-directory")

    await ssh.close()
  }

  @Test func testStatAndSetPermissions() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    // Prepare a temp file
    _ = try await ssh.execute(command: "rm -f /tmp/sftp-perm.txt && touch /tmp/sftp-perm.txt")

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
