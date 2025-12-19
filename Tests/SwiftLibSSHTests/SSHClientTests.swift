import Foundation
import Testing

@testable import SwiftLibSSH

struct SSHClientTests {
  @Test func testExecute() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let actual = try await client.execute("whoami")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let expected = "myuser"
    #expect(actual == expected)

    await client.close()
  }

  @Test func testExecuteWithLargerOutput() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass")

    let actual = try await client.execute("cat lorem-ipsum.txt")
      .decoded(as: .utf8)

    let expected = try String(contentsOfFile: "Tests/Data/lorem-ipsum.txt", encoding: .utf8)
    #expect(actual == expected)

    await client.close()
  }

  @Test func testPrivateKeyAuthentication() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: "Tests/Data/id_ed25519"
    )

    let actual = try await client.execute("whoami")
      .decoded(as: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let expected = "myuser"
    #expect(actual == expected)

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
      let _ = try await client.execute("whoami")
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
