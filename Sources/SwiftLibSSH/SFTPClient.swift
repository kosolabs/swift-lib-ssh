import Foundation

struct SFTPClient {
  let session: SSHSession
  let id: UUID

  init(session: SSHSession, id: UUID) {
    self.session = session
    self.id = id
  }

  func close() async {
    await session.sftpFree(id)
  }

  func mkdir(path: String, mode: mode_t = 0o755) async throws {
    try await session.sftpMkdir(id, path, mode: mode)
  }
}
