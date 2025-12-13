import Foundation

public struct SSHKey: Sendable {
  private let session: SSHSession
  private let id: UUID

  init(session: SSHSession, id: UUID) {
    self.session = session
    self.id = id
  }

  public func authenticate(user: String) async throws {
    try await session.authenticateWithPublicKey(id: id, user: user)
  }

  public func free() async {
    await session.freeKey(id: id)
  }
}
