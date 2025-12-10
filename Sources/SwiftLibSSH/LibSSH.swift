import CLibSSH
import Foundation

final class SSHKey: @unchecked Sendable {
  let session: SSHSession
  let key: ssh_key

  init(session: SSHSession, key: ssh_key) {
    self.session = session
    self.key = key
  }

  func free() async {
    await session.keyFree(key)
  }
}

final class SSHChannel: @unchecked Sendable {
  let session: SSHSession
  let channel: ssh_channel

  init(session: SSHSession, channel: ssh_channel) throws {
    self.session = session
    self.channel = channel
  }

  func free() async {
    await session.channelFree(channel)
  }

  func openSession() async throws {
    try await session.channelOpenSession(channel)
  }

  func requestExec(_ command: String) async throws {
    try await session.channelRequestExec(channel, command)
  }

  func read(bufferSize: Int = 1024) async throws -> Data {
    try await session.channelRead(channel, bufferSize: bufferSize)
  }

  func close() async {
    await session.channelClose(channel)
  }
}

enum SSHError: Error {
  case newFailed
  case optionsSetFailed(String)
  case userauthAgentFailed(String)
  case userauthPasswordFailed(String)
  case userauthPublickeyFailed(String)
  case pkiImportPrivkeyFile(String)
  case connectFailed(String)
  case channelNewFailed
  case channelReadFailed(String)
  case channelOpenSessionFailed(String)
  case channelRequestExecFailed(String)
}

final actor SSHSession {
  let session: ssh_session

  init() throws {
    guard let session: ssh_session = ssh_new() else {
      throw SSHError.newFailed
    }
    self.session = session
  }

  func free() {
    ssh_free(session)
  }

  // MARK: - Helper

  private func getError() -> String {
    String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
  }

  // MARK: - Session Operations

  func optionsSet(_ option: ssh_options_e, _ value: UnsafeRawPointer) throws {
    guard ssh_options_set(session, option, value) == SSH_OK else {
      throw SSHError.optionsSetFailed(getError())
    }
  }

  func setHost(_ host: String) throws {
    try optionsSet(SSH_OPTIONS_HOST, host)
  }

  func setPort(_ port: UInt32) throws {
    var port = port
    try optionsSet(SSH_OPTIONS_PORT, &port)
  }

  func connect() throws {
    guard ssh_connect(session) == SSH_OK else {
      throw SSHError.connectFailed(getError())
    }
  }

  func userauthAgent(_ user: String) throws {
    guard ssh_userauth_agent(session, user) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHError.userauthAgentFailed(getError())
    }
  }

  func userauthPassword(_ user: String, _ password: String) throws {
    guard ssh_userauth_password(session, user, password) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHError.userauthPasswordFailed(getError())
    }
  }

  func userauthPublickey(_ user: String, _ privateKey: SSHKey) throws {
    guard ssh_userauth_publickey(session, user, privateKey.key) == SSH_AUTH_SUCCESS.rawValue
    else {
      throw SSHError.userauthPublickeyFailed(getError())
    }
  }

  func isConnected() -> Bool {
    ssh_is_connected(session) == 1
  }

  func disconnect() {
    ssh_disconnect(session)
  }

  // MARK: - Key Operations

  func withPkiImportPrivkeyFile<T>(
    _ privateKeyPath: String, _ passphrase: String? = nil,
    _ body: (SSHKey) async throws -> T
  ) async throws -> T {
    let key = try pkiImportPrivkeyFile(privateKeyPath, passphrase)
    defer { keyFree(key.key) }
    return try await body(key)
  }

  func pkiImportPrivkeyFile(_ privateKeyPath: String, _ passphrase: String? = nil) throws -> SSHKey
  {
    var key: ssh_key?
    guard ssh_pki_import_privkey_file(privateKeyPath, passphrase, nil, nil, &key) == SSH_OK
    else {
      throw SSHError.pkiImportPrivkeyFile(getError())
    }

    return SSHKey(session: self, key: key!)
  }

  func keyFree(_ key: ssh_key) {
    ssh_key_free(key)
  }

  // MARK: - Channel Operations

  func withChannel<T>(
    _ body: (SSHChannel) async throws -> T
  ) async throws -> T {
    let channel = try channelNew()
    defer { channelFree(channel.channel) }
    return try await body(channel)
  }

  func channelNew() throws -> SSHChannel {
    guard let channel = ssh_channel_new(session) else {
      throw SSHError.newFailed
    }
    return try SSHChannel(session: self, channel: channel)
  }

  func channelFree(_ channel: ssh_channel) {
    ssh_channel_free(channel)
  }

  func channelOpenSession(_ channel: ssh_channel) throws {
    guard ssh_channel_open_session(channel) == SSH_OK else {
      throw SSHError.channelOpenSessionFailed(getError())
    }
  }

  func channelClose(_ channel: ssh_channel) {
    _ = ssh_channel_close(channel)
  }

  func channelRequestExec(_ channel: ssh_channel, _ command: String) throws {
    guard ssh_channel_request_exec(channel, command) == SSH_OK else {
      throw SSHError.channelRequestExecFailed(getError())
    }
  }

  func channelRead(_ channel: ssh_channel, bufferSize: Int = 1024) throws -> Data {
    var buffer = [CChar](repeating: 0, count: bufferSize)
    let bytesRead = ssh_channel_read(channel, &buffer, UInt32(bufferSize), 0)

    if bytesRead < 0 {
      throw SSHError.channelReadFailed(getError())
    }

    return Data(bytes: buffer, count: Int(bytesRead))
  }
}
