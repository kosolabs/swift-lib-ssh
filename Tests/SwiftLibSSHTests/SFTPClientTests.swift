import Foundation
import Testing

@testable import SwiftLibSSH

struct SFTPClientTests {
  @Test func mkdir() async throws {
    let ssh = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    // Ensure /tmp/test-directory doesn't exist
    _ = try await ssh.execute("rm -rf /tmp/test-directory")
    let before = try await ssh.execute("ls /tmp")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(before == "")

    try await ssh.withSftp({ sftp in
      try await sftp.mkdir(path: "/tmp/test-directory")
    })

    let after = try await ssh.execute("ls /tmp")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(after == "test-directory")

    await ssh.close()
  }
}
