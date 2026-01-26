import CLibSSH
import Foundation

public enum AccessType: Sendable {
  case readOnly
  case writeOnly
  case readWrite

  func raw(create: Bool = true, truncate: Bool = true) -> Int32 {
    switch self {
    case .readOnly:
      return O_RDONLY
    case .writeOnly:
      var result = O_WRONLY
      if create {
        result = result | O_CREAT
      }
      if truncate {
        result = result | O_TRUNC
      }
      return result
    case .readWrite:
      var result = O_RDWR
      if create {
        result = result | O_CREAT
      }
      if truncate {
        result = result | O_TRUNC
      }
      return result
    }
  }
}

public enum StreamType: Int32, Sendable {
  case stdout = 0
  case stderr = 1
}

// MARK: - Identifiers

public struct SSHKeyID: Hashable, Sendable {
  let uuid = UUID()
}

public struct SSHChannelID: Hashable, Sendable {
  let uuid = UUID()
}

public struct SFTPClientID: Hashable, Sendable {
  let uuid = UUID()
}

public struct SFTPFileID: Hashable, Sendable {
  let uuid = UUID()
}

public struct SFTPAioID: Hashable, Sendable {
  let fileId: SFTPFileID
  let uuid = UUID()

  init(fileId: SFTPFileID) {
    self.fileId = fileId
  }
}

public enum SSHError: Error {
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
  case channelGetExitStateFailed(String)
  case sftpNewFailed
  case sftpNotFound
  case sftpInitFailed(String)
  case sftpMkdirFailed(String)
  case sftpRmdirFailed(String)
  case sftpStatFailed(String)
  case sftpLstatFailed(String)
  case sftpSetstatFailed(String)
  case sftpLimitsFailed(String)
  case sftpFileNotFound
  case sftpOpenFailed(String)
  case sftpCloseFailed(String)
  case sftpSeekFailed(String)
  case sftpReadFailed(String)
  case sftpWriteFailed(String)
  case sftpAioNotFound
  case sftpAioBeginReadFailed(String)
  case sftpAioWaitReadFailed(String)
  case sftpAioBeginWriteFailed(String)
}

final actor SSHSession {
  static let BufferSize = 102400

  private var session: ssh_session?
  private var keys: [SSHKeyID: ssh_key] = [:]
  private var channels: [SSHChannelID: ssh_channel] = [:]
  private var sftps: [SFTPClientID: sftp_session] = [:]

  private struct TrackedFile {
    let file: sftp_file
    var aios: [SFTPAioID: UnsafeMutablePointer<sftp_aio?>] = [:]
  }
  private var files: [SFTPFileID: TrackedFile] = [:]

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
    _id: SSHKeyID = SSHKeyID(), from file: URL, passphrase: String? = nil,
    perform body: (SSHKey) async throws -> T
  ) async throws -> T {
    let key = try importPrivateKey(_id: _id, from: file, passphrase: passphrase)
    defer { freeKey(id: _id) }
    return try await body(key)
  }

  func importPrivateKey(
    _id: SSHKeyID = SSHKeyID(), from file: URL, passphrase: String? = nil
  ) throws -> SSHKey {
    var key: ssh_key?
    guard ssh_pki_import_privkey_file(file.path, passphrase, nil, nil, &key) == SSH_OK
    else {
      throw SSHError.pkiImportPrivkeyFile(getError())
    }

    keys[_id] = key!
    return SSHKey(session: self, id: _id)
  }

  func withImportedPrivateKey<T>(
    _id: SSHKeyID = SSHKeyID(), from base64: String, passphrase: String? = nil,
    perform body: (SSHKey) async throws -> T
  ) async throws -> T {
    let key = try importPrivateKey(_id: _id, from: base64, passphrase: passphrase)
    defer { freeKey(id: _id) }
    return try await body(key)
  }

  func importPrivateKey(
    _id: SSHKeyID = SSHKeyID(), from base64: String, passphrase: String? = nil
  ) throws -> SSHKey {
    var key: ssh_key?
    guard ssh_pki_import_privkey_base64(base64, passphrase, nil, nil, &key) == SSH_OK
    else {
      throw SSHError.pkiImportPrivkeyFile(getError())
    }

    keys[_id] = key!
    return SSHKey(session: self, id: _id)
  }

  func authenticateWithPublicKey(id: SSHKeyID, user: String) throws {
    guard let key = keys[id] else {
      throw SSHError.userauthPublickeyFailed("Key not found")
    }
    guard ssh_userauth_publickey(session, user, key) == SSH_AUTH_SUCCESS.rawValue
    else {
      throw SSHError.userauthPublickeyFailed(getError())
    }
  }

  func freeKey(id: SSHKeyID) {
    guard let key = keys.removeValue(forKey: id) else { return }
    ssh_key_free(key)
  }

  // MARK: - Channel Operations

  private func channel(id: SSHChannelID) throws -> ssh_channel {
    guard let channel = channels[id] else {
      throw SSHError.channelNotFound
    }
    return channel
  }

  func withSessionChannel<T>(
    _id: SSHChannelID = SSHChannelID(),
    perform body: @Sendable (SSHSessionChannel) async throws -> T
  ) async throws -> T {
    let channel = try openChannelSession(_id: _id)
    defer { closeChannel(id: _id) }
    return try await body(channel)
  }

  func openChannelSession(_id: SSHChannelID = SSHChannelID()) throws -> SSHSessionChannel {
    guard let channel = ssh_channel_new(session) else {
      throw SSHError.channelNewFailed
    }
    guard ssh_channel_open_session(channel) == SSH_OK else {
      ssh_channel_free(channel)
      throw SSHError.channelOpenSessionFailed(getError())
    }
    channels[_id] = channel
    return SSHSessionChannel(session: self, id: _id)
  }

  func closeChannel(id: SSHChannelID) {
    guard let channel = channels.removeValue(forKey: id) else { return }
    _ = ssh_channel_close(channel)
    ssh_channel_free(channel)
  }

  func execute(onChannel id: SSHChannelID, command: String) throws {
    let channel = try channel(id: id)
    guard ssh_channel_request_exec(channel, command) == SSH_OK else {
      throw SSHError.channelRequestExecFailed(getError())
    }
  }

  func exitState(onChannel id: SSHChannelID) throws -> SSHExitStatus {
    let channel = try channel(id: id)

    var code: Int32 = 0
    var signal: UnsafeMutablePointer<CChar>? = nil
    var coreDumped: Int32 = 0

    guard ssh_channel_get_exit_state(channel, &code, &signal, &coreDumped) == SSH_OK else {
      throw SSHError.channelGetExitStateFailed(getError())
    }
    defer { ssh_string_free_char(signal) }

    return SSHExitStatus.from(code: code, signal: signal, coreDumped: coreDumped)
  }

  func readChannel(
    id: SSHChannelID, into buffer: inout Data, length: Int, stream: StreamType
  ) throws -> Int {
    let channel = try channel(id: id)
    let bytesRead = buffer.withUnsafeMutableBytes({ raw in
      Int(ssh_channel_read(channel, raw.baseAddress, UInt32(length), stream.rawValue))
    })

    if bytesRead < 0 {
      throw SSHError.channelReadFailed(getError())
    }

    return bytesRead
  }

  // MARK: - SFTP Operations

  func sftp(id: SFTPClientID) throws -> sftp_session {
    guard let sftp = sftps[id] else {
      throw SSHError.sftpNotFound
    }
    return sftp
  }

  func withSftp<T>(
    _id: SFTPClientID = SFTPClientID(),
    perform body: (SFTPClient) async throws -> T
  ) async throws -> T {
    let sftp = try createSftp(_id: _id)
    defer { freeSftp(id: _id) }
    return try await body(sftp)
  }

  func createSftp(_id: SFTPClientID = SFTPClientID()) throws -> SFTPClient {
    guard let sftp = sftp_new(session) else {
      throw SSHError.sftpNewFailed
    }
    guard sftp_init(sftp) == SSH_OK else {
      throw SSHError.sftpInitFailed(getError())
    }
    sftps[_id] = sftp
    return SFTPClient(session: self, id: _id)
  }

  func freeSftp(id: SFTPClientID) {
    guard let sftp = sftps.removeValue(forKey: id) else { return }
    sftp_free(sftp)
  }

  func mkdir(id: SFTPClientID, atPath path: String, mode: mode_t = 0o755) throws {
    let sftp = try sftp(id: id)
    guard sftp_mkdir(sftp, path, mode) == SSH_OK else {
      throw SSHError.sftpMkdirFailed(getError())
    }
  }

  func rmdir(id: SFTPClientID, atPath path: String) throws {
    let sftp = try sftp(id: id)
    guard sftp_rmdir(sftp, path) == SSH_OK else {
      throw SSHError.sftpMkdirFailed(getError())
    }
  }

  func stat(id: SFTPClientID, path: String) throws -> SFTPAttributes {
    let sftp = try sftp(id: id)
    guard let attributes = sftp_stat(sftp, path) else {
      throw SSHError.sftpStatFailed(getError())
    }
    defer { sftp_attributes_free(attributes) }
    return SFTPAttributes.from(raw: attributes.pointee)
  }

  func setMode(id: SFTPClientID, path: String, mode: mode_t) throws {
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

  func limits(id: SFTPClientID) throws -> SFTPLimits {
    let sftp = try sftp(id: id)
    guard let raw = sftp_limits(sftp) else {
      throw SSHError.sftpLimitsFailed(getError())
    }
    defer { sftp_limits_free(raw) }
    return SFTPLimits.from(raw: raw.pointee)
  }

  // MARK: - SFTP File

  func file(id: SFTPFileID) throws -> sftp_file {
    guard let trackedFile = files[id] else {
      throw SSHError.sftpFileNotFound
    }
    return trackedFile.file
  }

  func withSftpFile<T>(
    _id: SFTPFileID = SFTPFileID(),
    id: SFTPClientID, path: String, accessType: AccessType, mode: mode_t = 0,
    perform body: (SFTPFile) async throws -> T
  ) async throws -> T {
    let file = try openFile(_id: _id, id: id, path: path, accessType: accessType, mode: mode)
    defer { closeFile(id: _id) }
    return try await body(file)
  }

  func openFile(
    _id: SFTPFileID = SFTPFileID(),
    id: SFTPClientID, path: String, accessType: AccessType, mode: mode_t = 0
  ) throws -> SFTPFile {
    let sftp = try sftp(id: id)
    guard let sftpFile = sftp_open(sftp, path, accessType.raw(), mode) else {
      throw SSHError.sftpOpenFailed(getError())
    }
    files[_id] = TrackedFile(file: sftpFile)
    return SFTPFile(session: self, id: _id)
  }

  func closeFile(id: SFTPFileID) {
    guard let trackedFile = files.removeValue(forKey: id) else { return }
    sftp_close(trackedFile.file)
    for aio in trackedFile.aios.values {
      freeAio(aio)
    }
  }

  func seekFile(id: SFTPFileID, offset: UInt64) throws {
    let file = try file(id: id)
    guard sftp_seek64(file, offset) == SSH_OK else {
      throw SSHError.sftpSeekFailed(getError())
    }
  }

  func readFile(id: SFTPFileID, into buffer: inout Data, length: Int) throws -> Int {
    let file = try file(id: id)

    let bytesRead = buffer.withUnsafeMutableBytes({ raw in
      sftp_read(file, raw.baseAddress, length)
    })

    if bytesRead < 0 {
      throw SSHError.sftpReadFailed(getError())
    }

    return bytesRead
  }

  func writeFile(id: SFTPFileID, data: Data) throws -> Int {
    let file = try file(id: id)

    let bufferSize = data.count
    let bytesWritten = data.withUnsafeBytes({ raw in
      sftp_write(file, raw.baseAddress, bufferSize)
    })

    if bytesWritten < 0 {
      throw SSHError.sftpWriteFailed(getError())
    }

    return bytesWritten
  }

  // MARK: - AIO

  private func freeAio(_ aio: UnsafeMutablePointer<sftp_aio?>) {
    sftp_aio_free(aio.pointee)
    aio.deallocate()
  }

  func withFreeingAio<T>(
    id: SFTPAioID,
    perform body: (UnsafeMutablePointer<sftp_aio?>) throws -> T
  ) throws -> T {
    guard let aio = files[id.fileId]?.aios.removeValue(forKey: id) else {
      throw SSHError.sftpAioNotFound
    }
    defer { freeAio(aio) }
    return try body(aio)
  }

  func beginRead(id: SFTPFileID, length: Int) throws -> SFTPAioReadContext {
    let aioId = SFTPAioID(fileId: id)
    let file = try file(id: id)
    let aio = UnsafeMutablePointer<sftp_aio?>.allocate(capacity: 1)
    files[id]?.aios[aioId] = aio

    if sftp_aio_begin_read(file, length, aio) < 0 {
      throw SSHError.sftpAioBeginReadFailed(getError())
    }

    return SFTPAioReadContext(session: self, id: aioId, length: length)
  }

  func waitRead(id: SFTPAioID, into buffer: inout Data, length: Int) throws -> Int {
    let bytesRead = try withFreeingAio(id: id) { aio in
      buffer.withUnsafeMutableBytes({ raw in
        sftp_aio_wait_read(aio, raw.baseAddress, length)
      })
    }

    if bytesRead < 0 {
      throw SSHError.sftpAioWaitReadFailed(getError())
    }

    return bytesRead
  }

  func beginWrite(id: SFTPFileID, buffer: Data, length: Int) throws -> SFTPAioWriteContext {
    let aioId = SFTPAioID(fileId: id)
    let file = try file(id: id)
    let aio = UnsafeMutablePointer<sftp_aio?>.allocate(capacity: 1)
    files[id]?.aios[aioId] = aio

    let bytesToWrite = buffer.withUnsafeBytes({ raw in
      sftp_aio_begin_write(file, raw.baseAddress, length, aio)
    })

    if bytesToWrite < 0 {
      throw SSHError.sftpAioBeginWriteFailed(getError())
    }

    return SFTPAioWriteContext(session: self, id: aioId, length: bytesToWrite)
  }

  func waitWrite(id: SFTPAioID) throws -> Int {
    try withFreeingAio(id: id) { aio in
      sftp_aio_wait_write(aio)
    }
  }
}
