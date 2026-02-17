import CryptoKit
import Foundation
import Testing

@testable import SwiftLibSSH

private var host: String {
  let env = ProcessInfo.processInfo.environment
  return env["SWIFT_LIBSSH_TEST_HOST"] ?? "localhost"
}

private var port: UInt16 {
  let env = ProcessInfo.processInfo.environment
  if let portString = env["SWIFT_LIBSSH_TEST_PORT"], let port = UInt16(portString) {
    return port
  }
  return 2222
}

private var user: String {
  let env = ProcessInfo.processInfo.environment
  return env["SWIFT_LIBSSH_TEST_USER"] ?? "myuser"
}

private var password: String {
  let env = ProcessInfo.processInfo.environment
  return env["SWIFT_LIBSSH_TEST_PASSWORD"] ?? "mypass"
}

private var privateKey: URL {
  let env = ProcessInfo.processInfo.environment
  return URL(fileURLWithPath: env["SWIFT_LIBSSH_TEST_PRIVATE_KEY_PATH"] ?? "Tests/Data/id_ed25519")
}

func client() async throws -> SSHClient {
  return try await SSHClient.connect(
    host: host, port: port, user: user, password: password)
}

@discardableResult
func withAuthenticatedClient<T: Sendable>(
  perform body: @Sendable (SSHClient) async throws -> T
) async throws -> T {
  let client = try await client()
  do {
    let result = try await body(client)
    await client.close()
    return result
  } catch {
    await client.close()
    throw error
  }
}

struct SSHAuthTests {
  @Test func testPasswordAuthentication() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, password: password
    ) { ssh in
      let proc = try await ssh.execute("whoami")
      let actual = try proc.stdout
        .decoded(as: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      let expected = user
      #expect(actual == expected)
      #expect(proc.status.code == 0)
    }
  }

  @Test func testPrivateKeyFileAuthentication() async throws {
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, privateKeyURL: privateKey
    ) { ssh in

      let proc = try await ssh.execute("whoami")
      let actual = try proc.stdout
        .decoded(as: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      let expected = user
      #expect(actual == expected)
      #expect(proc.status.code == 0)
    }
  }

  @Test func testBase64PrivateKeyAuthentication() async throws {
    let privateKey = try String(contentsOf: privateKey, encoding: .utf8)
    try await SSHClient.withAuthenticatedClient(
      host: host, port: port, user: user, base64PrivateKey: privateKey
    ) { ssh in

      let proc = try await ssh.execute("whoami")
      let actual = try proc.stdout
        .decoded(as: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      let expected = user
      #expect(actual == expected)
      #expect(proc.status.code == 0)
    }
  }

  @Test func testNoPasswordThrowsAuthenticationFailed() async throws {
    await #expect {
      try await SSHClient.connect(host: host, port: port, user: user)
    } throws: { error in
      (error as? SSHError)?.isAuthenticationFailed == true
    }
  }

  @Test func testBadPasswordThrowsAuthenticationFailed() async throws {
    await #expect {
      try await SSHClient.connect(host: host, port: port, user: user, password: "bad")
    } throws: { error in
      (error as? SSHError)?.isAuthenticationFailed == true
    }
  }

  @Test func testMissingPrivateKeyThrowsAuthenticationFailed() async throws {
    await #expect {
      try await SSHClient.connect(
        host: host, port: port, user: user, privateKeyURL: URL(filePath: "/tmp/missing_pk"))
    } throws: { error in
      (error as? SSHError)?.isAuthenticationFailed == true
    }
  }

  @Test func testInvalidHostThrowsConnectionFailed() async throws {
    await #expect {
      try await SSHClient.connect(host: "invalid", user: user)
    } throws: { error in
      (error as? SSHError)?.isConnectionFailed == true
    }
  }

  @Test func testInvalidPortThrowsConnectionFailed() async throws {
    await #expect {
      try await SSHClient.connect(host: host, port: 2200, user: user)
    } throws: { error in
      (error as? SSHError)?.isConnectionFailed == true
    }
  }

  @Test func testTimeoutThrowsConnectionFailed() async throws {
    await #expect {
      try await SSHClient.connect(host: "192.0.2.1", user: user)
    } throws: { error in
      (error as? SSHError)?.isConnectionFailed == true
    }
  }
}
