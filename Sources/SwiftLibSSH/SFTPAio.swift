import Foundation

public struct SFTPAio: Sendable {
  private let session: SSHSession
  private let id: SFTPAioID

  init(session: SSHSession, id: SFTPAioID) {
    self.session = session
    self.id = id
  }

  func free() async {
    await session.freeAio(id: id)
  }

  func read(into buffer: inout Data, count: Int) async throws {
    try await session.waitRead(id: id, into: &buffer, count: count)
  }
}
