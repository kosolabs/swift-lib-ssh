import CLibSSH
import Foundation

enum SSHError: Error {
  case newFailed
  case optionsSetFailed(String)
  case userauthAgentFailed(String)
  case userauthPasswordFailed(String)
  case userauthPublickeyFailed(String)
  case pkiImportPrivkeyFile(String)
  case channelNewFailed
  case channelNotFound
  case connectFailed(String)
  case channelOpenSessionFailed(String)
  case channelReadFailed(String)
  case channelRequestExecFailed(String)
  case sftpNewFailed
  case sftpNotFound
  case sftpInitFailed(String)
  case sftpMkdirFailed(String)
  case sftpStatFailed(String)
  case sftpLstatFailed(String)
  case sftpSetstatFailed(String)
}

final actor SSHSession {
  private var session: ssh_session?
  private var keys: [UUID: ssh_key] = [:]
  private var channels: [UUID: ssh_channel] = [:]
  private var sftps: [UUID: sftp_session] = [:]

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

  func setOption(_ option: ssh_options_e, to value: UnsafeRawPointer) throws {
    guard ssh_options_set(session, option, value) == SSH_OK else {
      throw SSHError.optionsSetFailed(getError())
    }
  }

  func setHost(_ host: String) throws {
    try setOption(SSH_OPTIONS_HOST, to: host)
  }

  func setPort(_ port: UInt32) throws {
    var port = port
    try setOption(SSH_OPTIONS_PORT, to: &port)
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

  func authenticate(user: String, password: String) throws {
    guard ssh_userauth_password(session, user, password) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHError.userauthPasswordFailed(getError())
    }
  }

  var isConnected: Bool {
    ssh_is_connected(session) == 1
  }

  func disconnect() {
    ssh_disconnect(session)
  }

  // MARK: - Key Operations

  func withImportedPrivateKey<T>(
    from path: String,
    passphrase: String? = nil,
    id: UUID = UUID(),
    perform body: (SSHKey) async throws -> T
  ) async throws -> T {
    let key = try importPrivateKey(from: path, passphrase: passphrase, id: id)
    defer { freeKey(id: id) }
    return try await body(key)
  }

  func importPrivateKey(
    from path: String, passphrase: String? = nil, id: UUID = UUID()
  ) throws -> SSHKey {
    var key: ssh_key?
    guard ssh_pki_import_privkey_file(path, passphrase, nil, nil, &key) == SSH_OK
    else {
      throw SSHError.pkiImportPrivkeyFile(getError())
    }

    keys[id] = key!
    return SSHKey(session: self, id: id)
  }

  func authenticateWithPublicKey(id: UUID, user: String) throws {
    guard let key = keys[id] else {
      throw SSHError.userauthPublickeyFailed("Key not found")
    }
    guard ssh_userauth_publickey(session, user, key) == SSH_AUTH_SUCCESS.rawValue
    else {
      throw SSHError.userauthPublickeyFailed(getError())
    }
  }

  func freeKey(id: UUID) {
    guard let key = keys.removeValue(forKey: id) else { return }
    ssh_key_free(key)
  }

  // MARK: - Channel Operations

  private func channel(id: UUID) throws -> ssh_channel {
    guard let channel = channels[id] else {
      throw SSHError.channelNotFound
    }
    return channel
  }

  func withChannel<T>(
    id: UUID = UUID(),
    perform body: (SSHChannel) async throws -> T
  ) async throws -> T {
    let channel = try createChannel(id: id)
    defer { freeChannel(id: id) }
    return try await body(channel)
  }

  func createChannel(id: UUID = UUID()) throws -> SSHChannel {
    guard let channel = ssh_channel_new(session) else {
      throw SSHError.channelNewFailed
    }
    channels[id] = channel
    return SSHChannel(session: self, id: id)
  }

  func freeChannel(id: UUID) {
    guard let channel = channels.removeValue(forKey: id) else { return }
    ssh_channel_free(channel)
  }

  func withOpenedChannelSession<T>(id: UUID, perform body: () async throws -> T) async throws -> T {
    let channel = try channel(id: id)
    try openChannelSession(channel: channel)
    defer { closeChannel(channel: channel) }
    return try await body()
  }

  private func openChannelSession(channel: ssh_channel) throws {
    guard ssh_channel_open_session(channel) == SSH_OK else {
      throw SSHError.channelOpenSessionFailed(getError())
    }
  }

  func openChannelSession(id: UUID) throws {
    try openChannelSession(channel: channel(id: id))
  }

  private func closeChannel(channel: ssh_channel) {
    _ = ssh_channel_close(channel)
  }

  func closeChannel(id: UUID) {
    guard let channel = channels[id] else { return }
    closeChannel(channel: channel)
  }

  func execute(onChannel id: UUID, command: String) throws {
    let channel = try channel(id: id)
    guard ssh_channel_request_exec(channel, command) == SSH_OK else {
      throw SSHError.channelRequestExecFailed(getError())
    }
  }

  func readChannel(id: UUID, into buffer: inout [UInt8]) throws -> Data? {
    let channel = try channel(id: id)

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

  // MARK: - SFTP Operations

  func sftp(id: UUID) throws -> sftp_session {
    guard let sftp = sftps[id] else {
      throw SSHError.sftpNotFound
    }
    return sftp
  }

  func withSftp<T>(
    id: UUID = UUID(),
    perform body: (SFTPClient) async throws -> T
  ) async throws -> T {
    let sftp = try await createSftp(id: id)
    defer { freeSftp(id: sftp.id) }
    return try await body(sftp)
  }

  func createSftp(id: UUID = UUID()) async throws -> SFTPClient {
    guard let sftp = sftp_new(session) else {
      throw SSHError.sftpNewFailed
    }
    guard sftp_init(sftp) == SSH_OK else {
      throw SSHError.sftpInitFailed(getError())
    }
    sftps[id] = sftp
    return SFTPClient(session: self, id: id)
  }

  func freeSftp(id: UUID) {
    guard let sftp = sftps.removeValue(forKey: id) else { return }
    sftp_free(sftp)
  }

  func makeDirectory(id: UUID, atPath path: String, mode: mode_t = 0o755) throws {
    let sftp = try sftp(id: id)
    guard sftp_mkdir(sftp, path, mode) == SSH_OK else {
      throw SSHError.sftpMkdirFailed(getError())
    }
  }

  func stat(id: UUID, path: String) throws -> SFTPAttributes {
    let sftp = try sftp(id: id)
    guard let attributes = sftp_stat(sftp, path) else {
      throw SSHError.sftpStatFailed(getError())
    }
    defer { sftp_attributes_free(attributes) }
    return SFTPAttributes.from(raw: attributes.pointee)
  }

  func lstat(id: UUID, path: String) throws -> SFTPAttributes {
    let sftp = try sftp(id: id)
    guard let attributes = sftp_lstat(sftp, path) else {
      throw SSHError.sftpLstatFailed(getError())
    }
    defer { sftp_attributes_free(attributes) }
    return SFTPAttributes.from(raw: attributes.pointee)
  }

  func setPermissions(id: UUID, path: String, mode: mode_t) throws {
    let sftp = try sftp(id: id)
    guard let attributes = sftp_stat(sftp, path) else {
      throw SSHError.sftpStatFailed(getError())
    }
    defer { sftp_attributes_free(attributes) }

    // Only set permissions flag (0x00000004) and value
    attributes.pointee.permissions = UInt32(mode)
    attributes.pointee.flags = 0x0000_0004
    guard sftp_setstat(sftp, path, attributes) == SSH_OK else {
      throw SSHError.sftpSetstatFailed(getError())
    }
  }
}
