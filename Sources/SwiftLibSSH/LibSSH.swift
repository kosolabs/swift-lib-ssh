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
  let sftpId: SFTPClientID
  let uuid = UUID()
}

public struct SFTPDirectoryID: Hashable, Sendable {
  let uuid = UUID()
}

public struct SFTPAioID: Hashable, Sendable {
  let fileId: SFTPFileID
  let uuid = UUID()

  init(fileId: SFTPFileID) {
    self.fileId = fileId
  }
}

public enum SFTPError: Error, Sendable, Equatable {
  case eof
  case noSuchFile
  case permissionDenied
  case failure
  case badMessage
  case noConnection
  case connectionLost
  case opUnsupported
  case invalidHandle
  case noSuchPath
  case fileAlreadyExists
  case writeProtect
  case noMedia

  static func from(code: Int32) -> SFTPError? {
    switch code {
    case SSH_FX_EOF: return .eof
    case SSH_FX_NO_SUCH_FILE: return .noSuchFile
    case SSH_FX_PERMISSION_DENIED: return .permissionDenied
    case SSH_FX_FAILURE: return .failure
    case SSH_FX_BAD_MESSAGE: return .badMessage
    case SSH_FX_NO_CONNECTION: return .noConnection
    case SSH_FX_CONNECTION_LOST: return .connectionLost
    case SSH_FX_OP_UNSUPPORTED: return .opUnsupported
    case SSH_FX_INVALID_HANDLE: return .invalidHandle
    case SSH_FX_NO_SUCH_PATH: return .noSuchPath
    case SSH_FX_FILE_ALREADY_EXISTS: return .fileAlreadyExists
    case SSH_FX_WRITE_PROTECT: return .writeProtect
    case SSH_FX_NO_MEDIA: return .noMedia
    default: return nil
    }
  }
}

public enum SSHError: Error, Sendable, Equatable {
  case connectionFailed(message: String)
  case authenticationFailed(message: String)
  case sftpError(SFTPError, message: String)
  case libraryError(code: Int32, message: String)
  case invalidState(message: String)

  static func from(code: Int32, message: String) -> SSHError {
    switch code {
    case Int32(SSH_FATAL.rawValue):
      return .connectionFailed(message: message)
    case Int32(SSH_REQUEST_DENIED.rawValue):
      return .authenticationFailed(message: message)
    default:
      return .libraryError(code: code, message: message)
    }
  }

  public var isConnectionFailed: Bool {
    if case .connectionFailed = self { return true }
    return false
  }

  public var isAuthenticationFailed: Bool {
    if case .authenticationFailed = self { return true }
    return false
  }

  public var sftpError: SFTPError? {
    guard case .sftpError(let error, _) = self else { return nil }
    return error
  }

  public var isLibraryError: Bool {
    if case .libraryError = self { return true }
    return false
  }

  public var isInvalidState: Bool {
    if case .invalidState = self { return true }
    return false
  }
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
  private var directories: [SFTPDirectoryID: sftp_dir] = [:]

  init() throws {
    guard let session: ssh_session = ssh_new() else {
      throw SSHError.invalidState(message: "Failed to initialize SSH session")
    }
    self.session = session
  }

  func free() {
    ssh_free(session)
    session = nil
  }

  // MARK: - Error Handling

  private func getErrorMessage() -> String {
    String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
  }

  private func getErrorCode() -> Int32 {
    ssh_get_error_code(UnsafeMutableRawPointer(session))
  }

  private func throwError(sftp: sftp_session? = nil) throws -> Never {
    let message = getErrorMessage()

    if let sftp = sftp {
      let sftpCode = sftp_get_error(sftp)
      if let sftpError = SFTPError.from(code: sftpCode) {
        throw SSHError.sftpError(sftpError, message: message)
      }
    }

    throw SSHError.from(code: getErrorCode(), message: message)
  }

  private func validate(_ code: Int, sftp: sftp_session? = nil) throws {
    try validate(Int32(code), sftp: sftp)
  }

  private func validate(_ code: Int32, sftp: sftp_session? = nil) throws {
    guard code == SSH_OK else {
      try throwError(sftp: sftp)
    }
  }

  private func validate<E>(_ value: E?, sftp: sftp_session? = nil) throws -> E {
    guard let value = value else {
      try throwError(sftp: sftp)
    }
    return value
  }

  // MARK: - Session Operations

  func setOption(_ option: ssh_options_e, to value: UnsafeRawPointer) throws {
    try validate(ssh_options_set(session, option, value))
  }

  func setHost(_ host: String) throws {
    try setOption(SSH_OPTIONS_HOST, to: host)
  }

  func setPort(_ port: UInt32) throws {
    var port = port
    try setOption(SSH_OPTIONS_PORT, to: &port)
  }

  func connect() throws {
    try validate(ssh_connect(session))
  }

  func userauthAgent(_ user: String) throws {
    try validate(ssh_userauth_agent(session, user))
  }

  func authenticate(user: String) throws {
    try validate(ssh_userauth_none(session, user))
  }

  func authenticate(user: String, password: String) throws {
    try validate(ssh_userauth_password(session, user, password))
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
    try validate(ssh_pki_import_privkey_file(file.path, passphrase, nil, nil, &key))

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
    try validate(ssh_pki_import_privkey_base64(base64, passphrase, nil, nil, &key))

    keys[_id] = key!
    return SSHKey(session: self, id: _id)
  }

  func authenticateWithPublicKey(id: SSHKeyID, user: String) throws {
    guard let key = keys[id] else {
      throw SSHError.invalidState(message: "Key \(id) not found")
    }
    try validate(ssh_userauth_publickey(session, user, key))
  }

  func freeKey(id: SSHKeyID) {
    guard let key = keys.removeValue(forKey: id) else { return }
    ssh_key_free(key)
  }

  // MARK: - Channel Operations

  private func channel(id: SSHChannelID) throws -> ssh_channel {
    guard let channel = channels[id] else {
      throw SSHError.invalidState(message: "Channel \(id) not found")
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
      throw SSHError.invalidState(message: "Failed to initialize SSH channel")
    }
    try validate(ssh_channel_open_session(channel))
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
    try validate(ssh_channel_request_exec(channel, command))
  }

  func exitState(onChannel id: SSHChannelID) throws -> SSHExitStatus {
    let channel = try channel(id: id)

    var code: Int32 = 0
    var signal: UnsafeMutablePointer<CChar>? = nil
    var coreDumped: Int32 = 0

    try validate(ssh_channel_get_exit_state(channel, &code, &signal, &coreDumped))
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
      try validate(bytesRead)
    }

    return bytesRead
  }

  // MARK: - SFTP Operations

  func sftp(id: SFTPClientID) throws -> sftp_session {
    guard let sftp = sftps[id] else {
      throw SSHError.invalidState(message: "SFTP session \(id) not found")
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
      throw SSHError.invalidState(message: "Failed to initialize SFTP client")
    }
    try validate(sftp_init(sftp))
    sftps[_id] = sftp
    return SFTPClient(session: self, id: _id)
  }

  func freeSftp(id: SFTPClientID) {
    guard let sftp = sftps.removeValue(forKey: id) else { return }
    sftp_free(sftp)
  }

  func mkdir(id: SFTPClientID, atPath path: String, mode: mode_t = 0o755) throws {
    let sftp = try sftp(id: id)
    try validate(sftp_mkdir(sftp, path, mode), sftp: sftp)
  }

  func rmdir(id: SFTPClientID, atPath path: String) throws {
    let sftp = try sftp(id: id)
    try validate(sftp_rmdir(sftp, path), sftp: sftp)
  }

  func stat(id: SFTPClientID, path: String) throws -> SFTPAttributes {
    let sftp = try sftp(id: id)
    let attributes = try validate(sftp_stat(sftp, path), sftp: sftp)
    defer { sftp_attributes_free(attributes) }
    return SFTPAttributes.from(raw: attributes.pointee)
  }

  func setMode(id: SFTPClientID, path: String, mode: mode_t) throws {
    let sftp = try sftp(id: id)
    let attributes = try validate(sftp_stat(sftp, path), sftp: sftp)
    defer { sftp_attributes_free(attributes) }

    // Only set permissions flag (0x00000004) and value
    attributes.pointee.permissions = UInt32(mode)
    attributes.pointee.flags = 0x0000_0004
    try validate(sftp_setstat(sftp, path, attributes), sftp: sftp)
  }

  func limits(id: SFTPClientID) throws -> SFTPLimits {
    let sftp = try sftp(id: id)
    let raw = try validate(sftp_limits(sftp), sftp: sftp)
    defer { sftp_limits_free(raw) }
    return SFTPLimits.from(raw: raw.pointee)
  }

  func rename(id: SFTPClientID, from: String, to: String) throws {
    let sftp = try sftp(id: id)
    try validate(sftp_rename(sftp, from, to), sftp: sftp)
  }

  func unlink(id: SFTPClientID, path: String) throws {
    let sftp = try sftp(id: id)
    try validate(sftp_unlink(sftp, path), sftp: sftp)
  }

  // MARK: - SFTP File

  func file(id: SFTPFileID) throws -> sftp_file {
    guard let trackedFile = files[id] else {
      throw SSHError.invalidState(message: "File \(id) not found")
    }
    return trackedFile.file
  }

  func withSftpFile<T>(
    _id: SFTPFileID? = nil,
    id: SFTPClientID, path: String, accessType: AccessType, mode: mode_t = 0,
    perform body: (SFTPFile) async throws -> T
  ) async throws -> T {
    let _id = _id ?? SFTPFileID(sftpId: id)
    let file = try openFile(_id: _id, id: id, path: path, accessType: accessType, mode: mode)
    defer { closeFile(id: _id) }
    return try await body(file)
  }

  func openFile(
    _id: SFTPFileID? = nil,
    id: SFTPClientID, path: String, accessType: AccessType, mode: mode_t = 0
  ) throws -> SFTPFile {
    let _id = _id ?? SFTPFileID(sftpId: id)
    let sftp = try sftp(id: id)
    let sftpFile = try validate(sftp_open(sftp, path, accessType.raw(), mode), sftp: sftp)
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

  func statFile(id: SFTPFileID) throws -> SFTPAttributes {
    let file = try file(id: id)
    let sftp = try sftp(id: id.sftpId)
    let attributes = try validate(sftp_fstat(file), sftp: sftp)
    defer { sftp_attributes_free(attributes) }
    return SFTPAttributes.from(raw: attributes.pointee)
  }

  func seekFile(id: SFTPFileID, offset: UInt64) throws {
    let file = try file(id: id)
    let sftp = try sftp(id: id.sftpId)
    try validate(sftp_seek64(file, offset), sftp: sftp)
  }

  func readFile(id: SFTPFileID, into buffer: inout Data, length: Int) throws -> Int {
    let file = try file(id: id)
    let sftp = try sftp(id: id.sftpId)

    let bytesRead = buffer.withUnsafeMutableBytes({ raw in
      sftp_read(file, raw.baseAddress, length)
    })

    if bytesRead < 0 {
      try validate(bytesRead, sftp: sftp)
    }

    return bytesRead
  }

  func writeFile(id: SFTPFileID, data: Data) throws -> Int {
    let file = try file(id: id)
    let sftp = try sftp(id: id.sftpId)

    let bufferSize = data.count
    let bytesWritten = data.withUnsafeBytes({ raw in
      sftp_write(file, raw.baseAddress, bufferSize)
    })

    if bytesWritten < 0 {
      try validate(bytesWritten, sftp: sftp)
    }

    return bytesWritten
  }

  // MARK: - SFTP Directory

  func directory(id: SFTPDirectoryID) throws -> sftp_dir {
    guard let dir = directories[id] else {
      throw SSHError.invalidState(message: "Directory \(id) not found")
    }
    return dir
  }

  func withDirectory<T: Sendable>(
    id: SFTPClientID, path: String,
    perform: @Sendable (SFTPDirectory) async throws -> T
  ) async throws -> T {
    let _id = SFTPDirectoryID()
    let dir = try openDirectory(_id: _id, id: id, path: path)
    defer { closeDirectory(id: _id) }
    return try await perform(dir)
  }

  func openDirectory(
    _id: SFTPDirectoryID,
    id: SFTPClientID, path: String
  ) throws -> SFTPDirectory {
    let sftp = try sftp(id: id)
    let dir = try validate(sftp_opendir(sftp, path), sftp: sftp)
    directories[_id] = dir
    return SFTPDirectory(session: self, sftpId: id, directoryId: _id)
  }

  func closeDirectory(id: SFTPDirectoryID) {
    guard let dir = directories.removeValue(forKey: id) else { return }
    sftp_closedir(dir)
  }

  func readDirectory(
    sftpId: SFTPClientID, directoryId: SFTPDirectoryID
  ) throws -> SFTPAttributes? {
    let sftp = try sftp(id: sftpId)
    let dir = try directory(id: directoryId)
    guard let attributes = sftp_readdir(sftp, dir) else {
      return nil
    }
    defer { sftp_attributes_free(attributes) }
    return SFTPAttributes.from(raw: attributes.pointee)
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
      throw SSHError.invalidState(message: "AIO \(id) not found")
    }
    defer { freeAio(aio) }
    return try body(aio)
  }

  func beginRead(id: SFTPFileID, length: Int) throws -> SFTPAioReadContext {
    let aioId = SFTPAioID(fileId: id)
    let file = try file(id: id)
    let sftp = try sftp(id: id.sftpId)
    let aio = UnsafeMutablePointer<sftp_aio?>.allocate(capacity: 1)
    files[id]?.aios[aioId] = aio

    let bytesToRead = sftp_aio_begin_read(file, length, aio)
    if bytesToRead < 0 {
      try validate(bytesToRead, sftp: sftp)
    }

    return SFTPAioReadContext(session: self, id: aioId, length: length)
  }

  func waitRead(id: SFTPAioID, into buffer: inout Data, length: Int) throws -> Int {
    let sftp = try sftp(id: id.fileId.sftpId)
    let bytesRead = try withFreeingAio(id: id) { aio in
      buffer.withUnsafeMutableBytes({ raw in
        sftp_aio_wait_read(aio, raw.baseAddress, length)
      })
    }

    if bytesRead < 0 {
      try validate(bytesRead, sftp: sftp)
    }

    return bytesRead
  }

  func beginWrite(id: SFTPFileID, buffer: Data, length: Int) throws -> SFTPAioWriteContext {
    let aioId = SFTPAioID(fileId: id)
    let file = try file(id: id)
    let sftp = try sftp(id: id.sftpId)
    let aio = UnsafeMutablePointer<sftp_aio?>.allocate(capacity: 1)
    files[id]?.aios[aioId] = aio

    let bytesToWrite = buffer.withUnsafeBytes({ raw in
      sftp_aio_begin_write(file, raw.baseAddress, length, aio)
    })

    if bytesToWrite < 0 {
      try validate(bytesToWrite, sftp: sftp)
    }

    return SFTPAioWriteContext(session: self, id: aioId, length: bytesToWrite)
  }

  func waitWrite(id: SFTPAioID) throws -> Int {
    try withFreeingAio(id: id) { aio in
      sftp_aio_wait_write(aio)
    }
  }
}
