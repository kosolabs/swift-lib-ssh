import Foundation

public enum SFTPClientError: Error {
  case openFileForWriteFailed
}

public struct SFTPClient: Sendable {
  private let session: SSHSession
  private let id: UUID

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

  func download(fromPath src: String, toPath dest: String) async throws {
    if !FileManager.default.fileExists(atPath: dest) {
      FileManager.default.createFile(atPath: dest, contents: nil)
    }

    guard let fp = FileHandle(forWritingAtPath: dest) else {
      throw SFTPClientError.openFileForWriteFailed
    }
    defer { try? fp.close() }

    try await session.withSftpFile(sftpId: id, path: src, accessType: O_RDONLY) { file in
      for try await data in file.stream() {
        if #available(macOS 10.15.4, *) {
          try fp.write(contentsOf: data)
        } else {
          fp.write(data)
        }
      }
    }
  }
}
