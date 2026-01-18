import CLibSSH
import Dispatch
import Foundation

public enum SSHClientError: Error {
  case connectionFailed(String)
  case authenticationFailed(String)
  case sessionError(String)
  case decodeFailed(String)
}

public struct SSHClient: Sendable {
  public typealias CommandResult = (status: SSHExitStatus, stdout: Data, stderr: Data)

  private let session: SSHSession

  private init(host: String, port: UInt32 = 22) async throws {
    self.session = try SSHSession()
    try await session.setHost(host)
    try await session.setPort(port)
  }

  private func connect() async throws {
    try await session.connect()
  }

  private func authenticate(
    user: String, password: String
  ) async throws {
    try await session.authenticate(user: user, password: password)
  }

  private func authenticate(
    user: String, privateKeyURL: URL, passphrase: String? = nil
  ) async throws {
    guard FileManager.default.fileExists(atPath: privateKeyURL.path) else {
      throw SSHClientError.authenticationFailed("Private key file not found: \(privateKeyURL)")
    }
    try await session.withImportedPrivateKey(from: privateKeyURL, passphrase: passphrase) {
      privateKey in
      try await privateKey.authenticate(user: user)
    }
  }

  public static func connect(
    host: String, port: UInt32 = 22, user: String, password: String
  ) async throws -> SSHClient {
    let client = try await SSHClient(host: host, port: port)
    try await client.connect()
    try await client.authenticate(user: user, password: password)
    return client
  }

  public static func connect(
    host: String, port: UInt32 = 22, user: String, privateKeyURL: URL, passphrase: String? = nil
  ) async throws
    -> SSHClient
  {
    let client = try await SSHClient(host: host, port: port)
    try await client.connect()
    try await client.authenticate(
      user: user, privateKeyURL: privateKeyURL, passphrase: passphrase)
    return client
  }

  @discardableResult
  public static func withAuthenticatedClient<T: Sendable>(
    host: String, port: UInt32 = 22, user: String, password: String,
    perform body: @Sendable (SSHClient) async throws -> T
  ) async throws -> T {
    let client = try await connect(
      host: host, port: port, user: user, password: password
    )
    do {
      let result = try await body(client)
      await client.close()
      return result
    } catch {
      await client.close()
      throw error
    }
  }

  @discardableResult
  public static func withAuthenticatedClient<T: Sendable>(
    host: String, port: UInt32 = 22, user: String,
    privateKeyURL: URL, passphrase: String? = nil,
    perform body: @Sendable (SSHClient) async throws -> T
  ) async throws -> T {
    let client = try await connect(
      host: host, port: port, user: user, privateKeyURL: privateKeyURL, passphrase: passphrase
    )
    do {
      let result = try await body(client)
      await client.close()
      return result
    } catch {
      await client.close()
      throw error
    }
  }

  public var isConnected: Bool {
    get async {
      await session.isConnected
    }
  }

  func isConnectedOrThrow() async throws {
    if await !isConnected {
      throw SSHClientError.sessionError("SSH session is closed")
    }
  }

  public func sftp() async throws -> SFTPClient {
    try await session.createSftp()
  }

  @discardableResult
  public func withSftp<T: Sendable>(
    perform body: @Sendable (SFTPClient) async throws -> T
  ) async throws -> T {
    try await session.withSftp(perform: body)
  }

  public func close() async {
    await session.disconnect()
    await session.free()
  }

  @discardableResult
  public func execute(_ command: String) async throws -> CommandResult {
    return try await execute(command) { channel in
      return try await (
        channel.exitStatus(),
        channel.read(from: .stdout),
        channel.read(from: .stderr)
      )
    }
  }

  public func execute<T: Sendable>(
    _ command: String,
    perform body: @Sendable (SSHSessionChannel) async throws -> T
  ) async throws -> T {
    try await isConnectedOrThrow()

    return try await session.withSessionChannel { channel in
      try await channel.execute(command: command)
      return try await body(channel)
    }
  }
}

extension Data {
  func decoded(as encoding: String.Encoding) throws -> String {
    guard let str = String(data: self, encoding: encoding) else {
      throw SSHClientError.decodeFailed("Failed to decode data as \(encoding)")
    }
    return str
  }
}
