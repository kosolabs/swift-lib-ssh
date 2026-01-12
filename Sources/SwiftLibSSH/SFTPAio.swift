import Foundation

public struct SFTPAio: Sendable {
  private let session: SSHSession
  private let id: SFTPAioID
  private let length: Int

  init(session: SSHSession, id: SFTPAioID, length: Int) {
    self.session = session
    self.id = id
    self.length = length
  }

  func free() async {
    await session.freeAio(id: id)
  }

  func read(into buffer: inout Data) async throws -> Int {
    try await session.waitRead(id: id, into: &buffer, length: length)
  }
}
