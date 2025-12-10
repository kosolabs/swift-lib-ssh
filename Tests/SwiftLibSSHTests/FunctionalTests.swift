import Foundation
import Testing

@testable import SwiftLibSSH

struct FunctionalTests {
  @Test
  func testPasswordAuthentication() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass"
    )
    defer { Task { await client.close() } }

    let command = "whoami"
    let output = try await client.execute(command)

    #expect(output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "myuser")
  }

  @Test
  func testPrivateKeyAuthentication() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: "", inDirectory: "Resources")!
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath
    )
    defer { Task { await client.close() } }

    let command = "whoami"
    let output = try await client.execute(command)

    #expect(output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "myuser")
  }

  @Test
  func testConnectedStatus() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: "", inDirectory: "Resources")!
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath)

    #expect(await client.isConnected())

    await client.close()

    #expect(!(await client.isConnected()))
  }

  @Test
  func testExecuteThrowsAfterClose() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: "", inDirectory: "Resources")!
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath)

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
