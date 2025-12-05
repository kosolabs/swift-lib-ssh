import XCTest

@testable import SwiftLibSSH

final class FunctionalTests: XCTestCase {
  func testPasswordAuthentication() async throws {
    let client = try SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", password: "mypass"
    )

    let command = "whoami"
    let output = try client.execute(command)

    XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "myuser")
  }

  func testPrivateKeyAuthentication() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: nil, inDirectory: "Resources")!
    let client = try SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath
    )

    let command = "whoami"
    let output = try client.execute(command)

    XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "myuser")
  }

  func testConnectedStatus() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: nil, inDirectory: "Resources")!
    let client = try SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath)

    XCTAssertTrue(client.connected)
    client.close()
    XCTAssertFalse(client.connected)
  }

  func testExecuteThrowsAfterClose() async throws {
    let privateKeyPath = Bundle.module.path(
      forResource: "id_ed25519", ofType: nil, inDirectory: "Resources")!
    let client = try SSHClient.connect(
      host: "localhost", port: 2222, user: "myuser", privateKeyPath: privateKeyPath)

    client.close()

    XCTAssertThrowsError(try client.execute("whoami")) { error in
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
