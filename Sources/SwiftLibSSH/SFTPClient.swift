import Foundation

public struct SFTPClient: Sendable {
  let session: SSHSession
  let id: UUID

  init(session: SSHSession, id: UUID) {
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
}
