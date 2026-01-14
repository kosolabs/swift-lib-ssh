import Foundation
import Testing

@testable import SwiftLibSSH

struct SSHClientTests {
  @Test func testExecute() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let proc = try await client.execute("whoami")
    let actual = try proc.stdout
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let expected = "myuser"
    #expect(actual == expected)
    #expect(proc.status.code == 0)

    await client.close()
  }

  @Test func testExecuteInvalidCommand() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let proc = try await client.execute("blah")

    #expect(proc.status.code == 127)

    await client.close()
  }

  @Test func testExecuteWithStderr() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let proc = try await client.execute("echo 'custom error' >&2")

    let stderr = try proc.stderr
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    #expect(stderr == "custom error")
    #expect(proc.status.code == 0)

    await client.close()
  }

  @Test func testExecuteWithSignal() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let proc = try await client.execute("kill -9 $$")

    #expect(proc.status.code == -1)
    #expect(proc.status.signal == "KILL")

    await client.close()
  }

  @Test func testExecuteWithCoreDump() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let proc = try await client.execute("bash -c 'ulimit -c unlimited; kill -ABRT $$'")

    #expect(proc.status.code == -1)
    #expect(proc.status.signal == "ABRT")
    #expect(proc.status.coreDumped == true)

    await client.close()
  }

  @Test func testExecuteWithLargerOutput() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let proc = try await client.execute("cat lorem-ipsum.txt")
    let actual = try proc.stdout.decoded(as: .utf8)

    let expected = try String(contentsOfFile: "Tests/Data/lorem-ipsum.txt", encoding: .utf8)
    #expect(actual == expected)
    #expect(proc.status.code == 0)

    await client.close()
  }

  @Test func testPrivateKeyAuthentication() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: "Tests/Data/id_ed25519"
    )

    let proc = try await client.execute("whoami")
    let actual = try proc.stdout
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let expected = "myuser"
    #expect(actual == expected)
    #expect(proc.status.code == 0)

    await client.close()
  }

  @Test func testConnectedStatus() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    #expect(await client.isConnected)

    await client.close()

    #expect(!(await client.isConnected))
  }

  @Test func testMultipleCallsToClose() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    #expect(await client.isConnected)

    await client.close()
    await client.close()

    #expect(!(await client.isConnected))
  }

  @Test func testExecuteThrowsAfterClose() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    await client.close()

    do {
      try await client.execute("whoami")
      Issue.record("Expected error to be thrown")
    } catch let error as SSHClientError {
      if case .sessionError(let message) = error {
        #expect(message == "SSH session is closed")
      } else {
        Issue.record("Expected sessionError, got \(error)")
      }
    } catch {
      Issue.record("Expected SSHClientError, got \(type(of: error))")
    }
  }
}
