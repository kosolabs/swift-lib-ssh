/// SSH Client module providing secure remote command execution over SSH.
///
/// This module contains the main SSH client implementation and error types for handling
/// SSH connections, authentication, and remote command execution.

import CLibSSH
import Foundation

/// Errors that can occur during SSH operations.
///
/// These errors represent various failure modes when connecting to SSH servers,
/// authenticating, or executing remote commands.
public enum SSHClientError: Error {
  /// Connection to the SSH server failed.
  ///
  /// - Parameter String: Error description detailing why the connection failed.
  case connectionFailed(String)

  /// Authentication with the SSH server failed.
  ///
  /// - Parameter String: Error description detailing why authentication failed.
  case authenticationFailed(String)

  /// SSH session operation failed.
  ///
  /// - Parameter String: Error description detailing the session error.
  case sessionError(String)

  /// SSH channel operation failed.
  ///
  /// - Parameter String: Error description detailing the channel error.
  case channelError(String)
}

/// A client for establishing SSH connections and executing remote commands.
///
/// `SSHClient` provides a Swift interface to the libssh library, enabling secure SSH connections
/// to remote servers. It supports multiple authentication methods (agent, password, and private key)
/// and allows execution of arbitrary commands on the remote server.
///
/// ## Authentication Methods
///
/// The client supports three primary authentication methods:
/// - **SSH Agent**: Automatically attempts to use keys from the SSH agent
/// - **Private Key**: Authenticates using an unencrypted or passphrase-protected private key file
/// - **Password**: Authenticates using a plaintext password
///
/// When connecting without specifying an authentication method, the client attempts to use the
/// SSH agent first, then falls back to default key locations if agent authentication fails.
///
/// ## Usage Example
///
/// ```swift
/// // Connect with SSH agent or default keys
/// let client = try SSHClient.connect(host: "example.com", user: "username")
///
/// // Execute a remote command
/// let output = try client.execute("ls -la")
/// print(output)
///
/// // Close the connection
/// client.close()
/// ```
///
/// ## Lifecycle
///
/// The SSH session is automatically closed and cleaned up in the deinitializer, but it's
/// recommended to explicitly call `close()` when done to ensure timely resource release.
final public class SSHClient {
  /// The underlying libssh session pointer.
  private var session: ssh_session? = nil

  /// Creates a new SSH session and connects to the specified host.
  ///
  /// - Parameters:
  ///   - host: The hostname or IP address to connect to.
  ///   - port: The port to connect to. Defaults to 22 (standard SSH port).
  ///
  /// - Throws: `SSHClientError.sessionError` if session creation fails.
  /// - Throws: `SSHClientError.connectionFailed` if connection to the host fails.
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

  /// Cleans up the SSH session when the client is deallocated.
  ///
  /// Automatically disconnects and frees the session resources.
  deinit {
    close()
  }

  /// Authenticates with the SSH server using the SSH agent or default key files.
  ///
  /// This method first attempts to authenticate using the SSH agent. If that fails,
  /// it tries the following default key paths:
  /// - `~/.ssh/id_rsa`
  /// - `~/.ssh/id_ecdsa`
  /// - `~/.ssh/id_ed25519`
  /// - `~/.ssh/id_dsa`
  ///
  /// - Parameter user: The username to authenticate as.
  ///
  /// - Throws: `SSHClientError.authenticationFailed` if all authentication methods fail.
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

  /// Connects to an SSH server using SSH agent or default key files.
  ///
  /// Establishes a connection to the specified host and authenticates using available
  /// SSH keys from the agent or default key locations.
  ///
  /// - Parameters:
  ///   - host: The hostname or IP address to connect to.
  ///   - port: The port to connect to. Defaults to 22 (standard SSH port).
  ///   - user: The username to authenticate as.
  ///
  /// - Returns: A connected and authenticated `SSHClient` instance.
  ///
  /// - Throws: `SSHClientError.connectionFailed` if connection fails.
  /// - Throws: `SSHClientError.authenticationFailed` if authentication fails.
  public static func connect(host: String, port: UInt32 = 22, user: String) throws
    -> SSHClient
  {
    let client = try SSHClient(host: host, port: port)
    try client.authenticate(user: user)
    return client
  }

  /// Authenticates with the SSH server using a password.
  ///
  /// - Parameters:
  ///   - user: The username to authenticate as.
  ///   - password: The password for the user.
  ///
  /// - Throws: `SSHClientError.authenticationFailed` if password authentication fails.
  private func authenticate(user: String, password: String) throws {
    guard ssh_userauth_password(session, user, password) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHClientError.authenticationFailed(get_error())
    }
  }

  /// Connects to an SSH server using password authentication.
  ///
  /// Establishes a connection to the specified host and authenticates using a password.
  ///
  /// - Parameters:
  ///   - host: The hostname or IP address to connect to.
  ///   - port: The port to connect to. Defaults to 22 (standard SSH port).
  ///   - user: The username to authenticate as.
  ///   - password: The password for the user.
  ///
  /// - Returns: A connected and authenticated `SSHClient` instance.
  ///
  /// - Throws: `SSHClientError.connectionFailed` if connection fails.
  /// - Throws: `SSHClientError.authenticationFailed` if password authentication fails.
  public static func connect(host: String, port: UInt32 = 22, user: String, password: String) throws
    -> SSHClient
  {
    let client = try SSHClient(host: host, port: port)
    try client.authenticate(user: user, password: password)
    return client
  }

  /// Authenticates with the SSH server using a private key.
  ///
  /// - Parameters:
  ///   - user: The username to authenticate as.
  ///   - privateKeyPath: The path to the private key file.
  ///   - passphrase: Optional passphrase for an encrypted private key. Pass `nil` for unencrypted keys.
  ///
  /// - Throws: `SSHClientError.authenticationFailed` if the key file is not found or authentication fails.
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

  /// Connects to an SSH server using private key authentication.
  ///
  /// Establishes a connection to the specified host and authenticates using the provided
  /// private key file.
  ///
  /// - Parameters:
  ///   - host: The hostname or IP address to connect to.
  ///   - port: The port to connect to. Defaults to 22 (standard SSH port).
  ///   - user: The username to authenticate as.
  ///   - privateKeyPath: The path to the private key file.
  ///   - passphrase: Optional passphrase for an encrypted private key. Pass `nil` for unencrypted keys.
  ///
  /// - Returns: A connected and authenticated `SSHClient` instance.
  ///
  /// - Throws: `SSHClientError.connectionFailed` if connection fails.
  /// - Throws: `SSHClientError.authenticationFailed` if the key file is not found or authentication fails.
  public static func connect(
    host: String, port: UInt32 = 22, user: String, privateKeyPath: String, passphrase: String? = nil
  ) throws
    -> SSHClient
  {
    let client = try SSHClient(host: host, port: port)
    try client.authenticate(user: user, privateKeyPath: privateKeyPath, passphrase: passphrase)
    return client
  }

  /// Validates that the SSH session is still active.
  ///
  /// - Returns: The session pointer if active.
  /// - Throws: `SSHClientError.sessionError` if the session is closed.
  private func get_session_or_throw() throws -> ssh_session {
    guard let session = self.session else {
      throw SSHClientError.sessionError("SSH session is closed")
    }
    return session
  }

  /// Retrieves the error message from the SSH session.
  ///
  /// - Returns: A human-readable error message describing the last SSH error.
  private func get_error() -> String {
    return String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
  }

  /// Indicates whether the SSH client is currently connected to the remote server.
  ///
  /// - Returns: `true` if connected, `false` otherwise.
  public var connected: Bool {
    guard let session = self.session else {
      return false
    }
    return ssh_is_connected(session) == 1
  }

  /// Closes the SSH connection and frees associated resources.
  ///
  /// Safe to call multiple times. After calling this method, the client cannot be reused.
  public func close() {
    if session != nil {
      ssh_disconnect(session)
      ssh_free(session)
    }
    session = nil
  }

  /// Executes a command on the remote SSH server and returns the output.
  ///
  /// This method creates an SSH channel, executes the specified command, and reads
  /// all output until EOF is reached. Both stdout is captured; stderr is typically
  /// redirected to stdout by the remote shell.
  ///
  /// - Parameter command: The command to execute on the remote server.
  ///
  /// - Returns: The command output as a UTF-8 decoded string.
  ///
  /// - Throws: `SSHClientError.sessionError` if the session is closed.
  /// - Throws: `SSHClientError.channelError` if channel creation or command execution fails.
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
