import CLibSSH
import Foundation

final class SSHKey: Sendable {
  let session: SSHSession
  let id: UUID

  init(session: SSHSession, id: UUID) {
    self.session = session
    self.id = id
  }

  func free() async {
    await session.keyFree(id)
  }
}

final class SSHChannel: Sendable {
  let session: SSHSession
  let id: UUID

  init(session: SSHSession, id: UUID) {
    self.session = session
    self.id = id
  }

  func free() async {
    await session.channelFree(id)
  }

  func openSession() async throws {
    try await session.channelOpenSession(id)
  }

  func requestExec(_ command: String) async throws {
    try await session.channelRequestExec(id, command)
  }

  func read(bufferSize: Int = 1024) async throws -> Data? {
    try await session.channelRead(id, bufferSize: bufferSize)
  }

  func stream(bufferSize: Int = 1024) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream(unfolding: {
      try await self.read(bufferSize: bufferSize)
    })
  }

  func close() async {
    await session.channelClose(id)
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
  private var keys: [UUID: ssh_key] = [:]
  private var channels: [UUID: ssh_channel] = [:]

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
    guard let key = keys[privateKey.id] else {
      throw SSHError.userauthPublickeyFailed("Key not found")
    }
    guard ssh_userauth_publickey(session, user, key) == SSH_AUTH_SUCCESS.rawValue
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
    defer { keyFree(key.id) }
    return try await body(key)
  }

  func pkiImportPrivkeyFile(_ privateKeyPath: String, _ passphrase: String? = nil) throws -> SSHKey
  {
    var key: ssh_key?
    guard ssh_pki_import_privkey_file(privateKeyPath, passphrase, nil, nil, &key) == SSH_OK
    else {
      throw SSHError.pkiImportPrivkeyFile(getError())
    }

    let id = UUID()
    keys[id] = key!
    return SSHKey(session: self, id: id)
  }

  func keyFree(_ id: UUID) {
    guard let key = keys.removeValue(forKey: id) else { return }
    ssh_key_free(key)
  }

  // MARK: - Channel Operations

  func withChannel<T>(
    _ body: (SSHChannel) async throws -> T
  ) async throws -> T {
    let channel = try channelNew()
    defer { channelFree(channel.id) }
    return try await body(channel)
  }

  func channelNew() throws -> SSHChannel {
    guard let channel = ssh_channel_new(session) else {
      throw SSHError.newFailed
    }
    let id = UUID()
    channels[id] = channel
    return SSHChannel(session: self, id: id)
  }

  func channelFree(_ id: UUID) {
    guard let channel = channels.removeValue(forKey: id) else { return }
    ssh_channel_free(channel)
  }

  func channelOpenSession(_ id: UUID) throws {
    guard let channel = channels[id] else {
      throw SSHError.channelOpenSessionFailed("Channel not found")
    }
    guard ssh_channel_open_session(channel) == SSH_OK else {
      throw SSHError.channelOpenSessionFailed(getError())
    }
  }

  func channelClose(_ id: UUID) {
    guard let channel = channels[id] else { return }
    _ = ssh_channel_close(channel)
  }

  func channelRequestExec(_ id: UUID, _ command: String) throws {
    guard let channel = channels[id] else {
      throw SSHError.channelRequestExecFailed("Channel not found")
    }
    guard ssh_channel_request_exec(channel, command) == SSH_OK else {
      throw SSHError.channelRequestExecFailed(getError())
    }
  }

  func channelRead(_ id: UUID, bufferSize: Int = 1024) throws -> Data? {
    guard let channel = channels[id] else {
      throw SSHError.channelReadFailed("Channel not found")
    }

    var buffer = [UInt8](repeating: 0, count: bufferSize)
    let bytesRead = buffer.withUnsafeMutableBytes { raw in
      ssh_channel_read(channel, raw.baseAddress, UInt32(bufferSize), 0)
    }

    if bytesRead < 0 {
      throw SSHError.channelReadFailed(getError())
    }

    if bytesRead == 0 {
      return nil
    }

    return Data(bytes: buffer, count: Int(bytesRead))
  }
}
