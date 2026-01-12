import Foundation

public struct SFTPClient: Sendable {
  private let session: SSHSession
  private let id: SFTPClientID

  init(session: SSHSession, id: SFTPClientID) {
    self.session = session
    self.id = id
  }

  func close() async {
    await session.freeSftp(id: id)
  }

  func makeDirectory(atPath path: String, mode: mode_t = 0o755) async throws {
    try await session.makeDirectory(id: id, atPath: path, mode: mode)
  }

  func stat(atPath path: String) async throws -> SFTPAttributes {
    try await session.stat(id: id, path: path)
  }

  func lstat(atPath path: String) async throws -> SFTPAttributes {
    try await session.lstat(id: id, path: path)
  }

  func setPermissions(atPath path: String, mode: mode_t) async throws {
    try await session.setPermissions(id: id, path: path, mode: mode)
  }

  func limits() async throws -> SFTPLimits {
    try await session.limits(id: id)
  }

  func withSftpFile<T: Sendable>(
    atPath path: String, accessType: AccessType, mode: mode_t = 0,
    perform: @Sendable (SFTPFile) async throws -> T
  ) async throws -> T {
    try await session.withSftpFile(
      id: id, path: path, accessType: accessType, mode: mode, perform: perform)
  }

  func download(
    from remotePath: String, to localURL: URL,
    progress: (@Sendable (UInt64) -> Void)? = nil
  ) async throws {
    try await withSftpFile(atPath: remotePath, accessType: .readOnly) { file in
      try await file.download(to: localURL, progress: progress)
    }
  }

  func upload(
    from localURL: URL, to remotePath: String, mode: mode_t = 0,
    progress: (@Sendable (UInt64) -> Void)? = nil
  ) async throws {
    try await withSftpFile(atPath: remotePath, accessType: .writeOnly, mode: mode) { file in
      try await file.upload(from: localURL, mode: mode, progress: progress)
    }
  }
}
