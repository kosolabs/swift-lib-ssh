import CLibSSH
import Dispatch
import Foundation

public enum SSHClientError: Error {
  case connectionFailed(String)
  case authenticationFailed(String)
  case sessionError(String)
}

public struct SSHClient: Sendable {
  private let session: SSHSession

  private init(host: String, port: UInt32 = 22) async throws {
    self.session = try SSHSession()
    try await session.setHost(host)
    try await session.setPort(port)
  }

  private func connect() async throws {
    try await session.connect()
  }

  public func authenticate(user: String) async throws {
    if (try? await session.userauthAgent(user)) != nil {
      return
    }

    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let defaultKeys = [
      "\(homeDir)/.ssh/id_rsa",
      "\(homeDir)/.ssh/id_ecdsa",
      "\(homeDir)/.ssh/id_ed25519",
      "\(homeDir)/.ssh/id_dsa",
    ]

    for keyPath in defaultKeys {
      if FileManager.default.fileExists(atPath: keyPath) {
        do {
          try await authenticate(user: user, privateKeyPath: keyPath)
          return
        } catch {
          // Continue to next key
        }
      }
    }

    throw SSHClientError.authenticationFailed("Failed to authenticate with agent or default keys")
  }

  public static func connect(host: String, port: UInt32 = 22, user: String) async throws
    -> SSHClient
  {
    let client = try await SSHClient(host: host, port: port)
    try await client.connect()
    try await client.authenticate(user: user)
    return client
  }

  private func authenticate(user: String, password: String) async throws {
    try await session.authenticate(user: user, password: password)
  }

  public static func connect(host: String, port: UInt32 = 22, user: String, password: String)
    async throws
    -> SSHClient
  {
    let client = try await SSHClient(host: host, port: port)
    try await client.connect()
    try await client.authenticate(user: user, password: password)
    return client
  }

  private func authenticate(user: String, privateKeyPath: String, passphrase: String? = nil)
    async throws
  {
    guard FileManager.default.fileExists(atPath: privateKeyPath) else {
      throw SSHClientError.authenticationFailed("Private key file not found: \(privateKeyPath)")
    }
    try await session.withImportedPrivateKey(from: privateKeyPath, passphrase: passphrase) {
      privateKey in
      try await privateKey.authenticate(user: user)
    }
  }

  public static func connect(
    host: String, port: UInt32 = 22, user: String, privateKeyPath: String, passphrase: String? = nil
  ) async throws
    -> SSHClient
  {
    let client = try await SSHClient(host: host, port: port)
    try await client.connect()
    try await client.authenticate(
      user: user, privateKeyPath: privateKeyPath, passphrase: passphrase)
    return client
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

  public func withSftp<T: Sendable>(
    perform body: @Sendable (SFTPClient) async throws -> T
  ) async throws -> T {
    try await session.withSftp(perform: body)
  }

  public func close() async {
    await session.disconnect()
    await session.free()
  }

  public func execute(command: String) async throws -> String {
    try await isConnectedOrThrow()

    return try await session.withChannel { channel in
      try await channel.withOpenedSession {
        try await channel.execute(command: command)

        var output = ""

        for try await data in channel.stream() {
          if let next = String(data: data, encoding: .utf8) {
            output.append(next)
          }
        }

        return output
      }
    }
  }
}
