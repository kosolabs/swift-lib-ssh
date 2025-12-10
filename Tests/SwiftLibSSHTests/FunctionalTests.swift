import SwiftAsyncAssert
import XCTest

@testable import SwiftLibSSH

final class FunctionalTests: XCTestCase {
  func testPasswordAuthentication() async throws {
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass"
    )
    defer { Task { await client.close() } }

    let command = "whoami"
    let output = try await client.execute(command)

    XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "myuser")
  }

  func testPrivateKeyAuthentication() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: nil, inDirectory: "Resources")!
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath
    )
    defer { Task { await client.close() } }

    let command = "whoami"
    let output = try await client.execute(command)

    XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "myuser")
  }

  func testConnectedStatus() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: nil, inDirectory: "Resources")!
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath)

    await AsyncAssertTrue(await client.isConnected())

    await client.close()

    await AsyncAssertFalse(await client.isConnected())
  }

  func testExecuteThrowsAfterClose() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: nil, inDirectory: "Resources")!
    let client = try await SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath)

    await client.close()

    await AsyncAssertThrowsError(try await client.execute("whoami")) { error in
      guard let sshError = error as? SSHClientError else {
        XCTFail("Expected SSHClientError, got \(type(of: error))")
        return
      }

      if case .sessionError(let message) = sshError {
        XCTAssertEqual(message, "SSH session is closed")
      } else {
        XCTFail("Expected sessionError, got \(sshError)")
      }
    }
  }
}
