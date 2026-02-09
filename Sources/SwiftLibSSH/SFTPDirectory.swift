import Foundation

public struct SFTPDirectory: Sendable, AsyncSequence {
  private let session: SSHSession
  private let sftpId: SFTPClientID
  private let directoryId: SFTPDirectoryID

  init(session: SSHSession, sftpId: SFTPClientID, directoryId: SFTPDirectoryID) {
    self.session = session
    self.sftpId = sftpId
    self.directoryId = directoryId
  }

  func read() async throws -> SFTPAttributes? {
    while true {
      guard
        let attrs = try await session.readDirectory(
          sftpId: sftpId, directoryId: directoryId)
      else {
        return nil
      }

      if attrs.name == "" || attrs.name == "." || attrs.name == ".." {
        continue
      }
      return attrs
    }
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(directory: self)
  }

  public struct Iterator: AsyncIteratorProtocol {
    private let directory: SFTPDirectory

    init(directory: SFTPDirectory) {
      self.directory = directory
    }

    public func next() async throws -> SFTPAttributes? {
      try await directory.read()
    }
  }
}
