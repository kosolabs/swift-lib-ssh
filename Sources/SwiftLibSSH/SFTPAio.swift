import Foundation

public struct SFTPAio: Sendable {
  private let session: SSHSession
  private let aioId: UUID
  private let fileId: UUID

  init(session: SSHSession, aioId: UUID, fileId: UUID) {
    self.session = session
    self.aioId = aioId
    self.fileId = fileId
  }

  func free() async {
    await session.freeAio(aioId: aioId, fileId: fileId)
  }

  func read(into buffer: inout [UInt8]) async throws -> Data? {
    try await session.waitRead(aioId: aioId, fileId: fileId, into: &buffer)
  }
}
