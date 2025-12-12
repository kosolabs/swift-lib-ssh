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

  func withSession<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
    try await session.withChannelSession(id, body)
  }

  func openSession() async throws {
    try await session.channelOpenSession(id)
  }

  func close() async {
    await session.channelClose(id)
  }

  func requestExec(_ command: String) async throws {
    try await session.channelRequestExec(id, command)
  }

  func read(buffer: inout [UInt8]) async throws -> Data? {
    try await session.channelRead(id, buffer: &buffer)
  }

  func read(bufferSize: Int = 1248) async throws -> Data? {
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    return try await read(buffer: &buffer)
  }

  func stream(bufferSize: Int = 1248) async -> AsyncThrowingStream<Data, Error> {
    return await session.channelStream(id, bufferSize: bufferSize)
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
  case channelNotFound
}

final actor SSHSession {
  var session: ssh_session?
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
    session = nil
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

  func withChannel<T>(_ body: (SSHChannel) async throws -> T) async throws -> T {
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

  private func channelFree(_ channel: ssh_channel) {
    ssh_channel_free(channel)
  }

  func channelFree(_ id: UUID) {
    guard let channel = channels.removeValue(forKey: id) else { return }
    channelFree(channel)
  }

  private func withChannelSession<T>(
    _ channel: ssh_channel, _ body: () async throws -> T
  ) async throws -> T {
    try channelOpenSession(channel)
    defer { channelClose(channel) }
    return try await body()
  }

  private func getChannel(_ id: UUID) throws -> ssh_channel {
    guard let channel = channels[id] else {
      throw SSHError.channelNotFound
    }
    return channel
  }

  func withChannelSession<T>(_ id: UUID, _ body: () async throws -> T) async throws -> T {
    return try await withChannelSession(getChannel(id), body)
  }

  private func channelOpenSession(_ channel: ssh_channel) throws {
    guard ssh_channel_open_session(channel) == SSH_OK else {
      throw SSHError.channelOpenSessionFailed(getError())
    }
  }

  func channelOpenSession(_ id: UUID) throws {
    try channelOpenSession(getChannel(id))
  }

  private func channelClose(_ channel: ssh_channel) {
    _ = ssh_channel_close(channel)
  }

  func channelClose(_ id: UUID) {
    guard let channel = channels[id] else { return }
    channelClose(channel)
  }

  private func channelRequestExec(_ channel: ssh_channel, _ command: String) throws {
    guard ssh_channel_request_exec(channel, command) == SSH_OK else {
      throw SSHError.channelRequestExecFailed(getError())
    }
  }

  func channelRequestExec(_ id: UUID, _ command: String) throws {
    try channelRequestExec(getChannel(id), command)
  }

  private func channelRead(_ channel: ssh_channel, buffer: inout [UInt8]) throws -> Data? {
    let bufferSize = buffer.count
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

  func channelRead(_ id: UUID, buffer: inout [UInt8]) throws -> Data? {
    return try channelRead(getChannel(id), buffer: &buffer)
  }

  func channelStream(
    _ id: UUID, bufferSize: Int = 1248
  ) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      guard let channel = channels[id] else {
        continuation.finish(throwing: SSHError.channelNotFound)
        return
      }

      let task = Task {
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while !Task.isCancelled {
          do {
            guard let data = try channelRead(channel, buffer: &buffer) else {
              continuation.finish()
              return
            }
            continuation.yield(data)
            await Task.yield()
          } catch {
            continuation.finish(throwing: error)
            return
          }
        }
      }

      continuation.onTermination = { @Sendable termination in
        if case .cancelled = termination {
          task.cancel()
        }
      }
    }
  }
}
