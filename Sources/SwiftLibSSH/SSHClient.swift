import CLibSSH
import Foundation

public enum SSHClientError: Error {
  case connectionFailed(String)
  case authenticationFailed(String)
  case sessionError(String)
  case channelError(String)
}

final public class SSHClient {
  private var session: ssh_session? = nil

  private init(host: String, port: UInt32 = 22) throws {
    guard let session = ssh_new() else {
      throw SSHClientError.sessionError("Failed to create SSH session")
    }
    self.session = session

    var port = port
    ssh_options_set(session, SSH_OPTIONS_HOST, host)
    ssh_options_set(session, SSH_OPTIONS_PORT, &port)

    guard ssh_connect(session) == SSH_OK else {
      throw SSHClientError.connectionFailed(get_error())
    }
  }

  deinit {
    close()
  }

  private func authenticate(user: String) throws {
    if ssh_userauth_agent(session, user) == SSH_AUTH_SUCCESS.rawValue {
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
          try authenticate(user: user, privateKeyPath: keyPath)
          return
        } catch {
          // Continue to next key
        }
      }
    }

    throw SSHClientError.authenticationFailed("Failed to authenticate with agent or default keys")
  }

  public static func connect(host: String, port: UInt32 = 22, user: String) throws
    -> SSHClient
  {
    let client = try SSHClient(host: host, port: port)
    try client.authenticate(user: user)
    return client
  }

  private func authenticate(user: String, password: String) throws {
    guard ssh_userauth_password(session, user, password) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHClientError.authenticationFailed(get_error())
    }
  }

  public static func connect(host: String, port: UInt32 = 22, user: String, password: String) throws
    -> SSHClient
  {
    let client = try SSHClient(host: host, port: port)
    try client.authenticate(user: user, password: password)
    return client
  }

  private func authenticate(user: String, privateKeyPath: String, passphrase: String? = nil) throws
  {
    guard FileManager.default.fileExists(atPath: privateKeyPath) else {
      throw SSHClientError.authenticationFailed("Private key file not found: \(privateKeyPath)")
    }
    var privateKey: ssh_key?
    guard ssh_pki_import_privkey_file(privateKeyPath, passphrase, nil, nil, &privateKey) == SSH_OK
    else {
      throw SSHClientError.authenticationFailed(get_error())
    }
    defer {
      ssh_key_free(privateKey)
    }
    guard ssh_userauth_publickey(session, user, privateKey) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHClientError.authenticationFailed(get_error())
    }
  }

  public static func connect(
    host: String, port: UInt32 = 22, user: String, privateKeyPath: String, passphrase: String? = nil
  ) throws
    -> SSHClient
  {
    let client = try SSHClient(host: host, port: port)
    try client.authenticate(user: user, privateKeyPath: privateKeyPath, passphrase: passphrase)
    return client
  }

  private func get_session_or_throw() throws -> ssh_session {
    guard let session = self.session else {
      throw SSHClientError.sessionError("SSH session is closed")
    }
    return session
  }

  private func get_error() -> String {
    return String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
  }

  public var connected: Bool {
    guard let session = self.session else {
      return false
    }
    return ssh_is_connected(session) == 1
  }

  public func close() {
    if session != nil {
      ssh_disconnect(session)
      ssh_free(session)
    }
    session = nil
  }

  public func execute(_ command: String) throws -> String {
    let session = try get_session_or_throw()

    guard let channel = ssh_channel_new(session) else {
      throw SSHClientError.channelError("Failed to create channel")
    }
    defer {
      ssh_channel_close(channel)
      ssh_channel_free(channel)
    }

    guard ssh_channel_open_session(channel) == SSH_OK else {
      throw SSHClientError.channelError(get_error())
    }

    guard ssh_channel_request_exec(channel, command) == SSH_OK else {
      throw SSHClientError.channelError(get_error())
    }

    var output = ""
    var buffer = [CChar](repeating: 0, count: 1024)

    while true {
      let bytesRead = ssh_channel_read(channel, &buffer, UInt32(buffer.count), 0)
      if bytesRead == 0 { break }
      if bytesRead < 0 {
        throw SSHClientError.channelError(get_error())
      }
      let data = Data(bytes: buffer, count: Int(bytesRead))
      if let next = String(data: data, encoding: .utf8) {
        output.append(next)
      }
    }

    return output
  }
}
