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
}
