import Foundation
import Testing

@testable import SwiftLibSSH

struct SSHClientTests {
  @Test func testExecute() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { client in

      let proc = try await client.execute("whoami")
      let actual = try proc.stdout
        .decoded(as: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      let expected = user
      #expect(actual == expected)
      #expect(proc.status.code == 0)
    }
  }

  @Test func testExecuteMoreThanOnce() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { client in

      let expected = user

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
    }
  }

  @Test func testExecuteInvalidCommand() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { client in

      let proc = try await client.execute("blah")

      #expect(proc.status.code == 127)
    }
  }

  @Test func testExecuteWithStderr() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { client in

      let proc = try await client.execute("echo 'custom error' >&2")

      let stderr = try proc.stderr
        .decoded(as: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      #expect(stderr == "custom error")
      #expect(proc.status.code == 0)
    }
  }

  @Test func testExecuteWithSignal() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { client in

      let proc = try await client.execute("kill -9 $$")

      #expect(proc.status.code == nil)
      #expect(proc.status.signal == "KILL")
    }
  }

  @Test func testExecuteWithLargerOutput() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { client in

      let proc = try await client.execute(
        "for i in {1..500}; do echo 'Hello world'; done"
      )
      let actual = try proc.stdout.decoded(as: .utf8)

      let expected = Array(repeating: "Hello world\n", count: 500).joined()
      #expect(actual == expected)
      #expect(proc.status.code == 0)
    }
  }

  @Test func testCancellationOfForAwaitLoopOverChannelStream() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { client in

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
    }
  }

  @Test func testPrivateKeyAuthentication() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, privateKeyURL: privateKey
    ) { client in

      let proc = try await client.execute("whoami")
      let actual = try proc.stdout
        .decoded(as: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      let expected = user
      #expect(actual == expected)
      #expect(proc.status.code == 0)
    }
  }

  @Test func testConnectedStatus() async throws {
    let client = try await SSHClient.connect(
      host: host, port: port, user: user, password: password)

    #expect(await client.isConnected)

    await client.close()

    #expect(!(await client.isConnected))
  }

  @Test func testMultipleCallsToClose() async throws {
    let client = try await SSHClient.connect(
      host: host, port: port, user: user, password: password)

    #expect(await client.isConnected)

    await client.close()
    await client.close()

    #expect(!(await client.isConnected))
  }

  @Test func testExecuteThrowsAfterClose() async throws {
    let client = try await SSHClient.connect(
      host: host, port: port, user: user, password: password)

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
