import Foundation

public struct SFTPClient: Sendable {
  private let session: SSHSession
  private let id: SFTPClientID

  init(session: SSHSession, id: SFTPClientID) {
    self.session = session
    self.id = id
  }

  public func close() async {
    await session.freeSftp(id: id)
  }

  public func createDirectory(atPath path: String, mode: mode_t = 0o755) async throws {
    try await session.mkdir(id: id, atPath: path, mode: mode)
  }

  public func removeDirectory(atPath path: String) async throws {
    try await session.rmdir(id: id, atPath: path)
  }

  public func withDirectory<T: Sendable>(
    atPath path: String, perform: @Sendable (SFTPDirectory) async throws -> T
  ) async throws -> T {
    try await session.withDirectory(id: id, path: path, perform: perform)
  }

  public func attributes(atPath path: String) async throws -> SFTPAttributes {
    try await session.stat(id: id, path: path)
  }

  public func setAttributes(
    atPath path: String,
    size: UInt64? = nil,
    uid: UInt32? = nil,
    gid: UInt32? = nil,
    permissions: mode_t? = nil,
    accessTime: Date? = nil,
    modifyTime: Date? = nil
  ) async throws {
    try await session.setStat(
      id: id,
      path: path,
      size: size,
      uid: uid,
      gid: gid,
      permissions: permissions,
      accessTime: accessTime,
      modifyTime: modifyTime
    )
  }

  public func move(from oldPath: String, to newPath: String) async throws {
    try await session.rename(id: id, from: oldPath, to: newPath)
  }

  public func removeFile(atPath path: String) async throws {
    try await session.unlink(id: id, path: path)
  }

  public func limits() async throws -> SFTPLimits {
    try await session.limits(id: id)
  }

  public func withSftpFile<T: Sendable>(
    atPath path: String, accessType: AccessType, mode: mode_t = 0,
    perform: @Sendable (SFTPFile) async throws -> T
  ) async throws -> T {
    try await session.withSftpFile(
      id: id, path: path, accessType: accessType, mode: mode, perform: perform
    )
  }

  public func download(
    from remotePath: String, to localURL: URL,
    progress: (@Sendable (UInt64) -> Void)? = nil
  ) async throws {
    try await withSftpFile(atPath: remotePath, accessType: .readOnly) { file in
      try await file.download(to: localURL, progress: progress)
    }
  }

  public func upload(
    from localURL: URL, to remotePath: String, mode: mode_t = 0,
    progress: (@Sendable (UInt64) -> Void)? = nil
  ) async throws {
    try await withSftpFile(atPath: remotePath, accessType: .writeOnly, mode: mode) { file in
      try await file.upload(from: localURL, mode: mode, progress: progress)
    }
  }
}
