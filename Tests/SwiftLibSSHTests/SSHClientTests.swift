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

  @Test func testExecuteMoreThanOnce() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let expected = "myuser"

    let actual1 = try await client.execute("whoami")
      .stdout
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(actual1 == expected)

    let actual2 = try await client.execute("whoami")
      .stdout
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(actual2 == expected)

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

    #expect(proc.status.code == nil)
    #expect(proc.status.signal == "KILL")

    await client.close()
  }

  @Test func testExecuteWithCoreDump() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let proc = try await client.execute("bash -c 'ulimit -c unlimited; kill -ABRT $$'")

    #expect(proc.status.code == nil)
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

  @Test func testCancellationOfForAwaitLoopOverChannelStream() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let expected = 1_000_000
    let actual = try await client.execute(
      "dd if=/dev/urandom bs=\(expected) count=1 of=/dev/stdout"
    ) { channel in
      for try await data: Data in channel.stream(from: .stdout) {
        // Returning here causes stream to cancel
        return data
      }
      fatalError("Stream should not complete")
    }

    #expect(actual.count > 0)
    #expect(actual.count < expected)

    await client.close()
  }

  @Test func testPrivateKeyAuthentication() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser",
      privateKeyURL: URL(fileURLWithPath: "Tests/Data/id_ed25519")
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
