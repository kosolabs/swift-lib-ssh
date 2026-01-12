import Foundation

public enum SFTPClientError: Error {
  case createFileFailed
  case openFileForWriteFailed
  case openFileForReadFailed
  case oops
}

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
    if FileManager.default.fileExists(atPath: localURL.path) {
      try FileManager.default.removeItem(at: localURL)
    }
    if !FileManager.default.createFile(atPath: localURL.path, contents: nil) {
      throw SFTPClientError.createFileFailed
    }

    guard let fp = try? FileHandle(forWritingTo: localURL) else {
      throw SFTPClientError.openFileForWriteFailed
    }
    defer { try? fp.close() }

    try await withSftpFile(atPath: remotePath, accessType: .readOnly) { file in
      var count: UInt64 = 0
      for try await data in file.stream() {
        try fp.write(contentsOf: data)
        count += UInt64(data.count)
        if let progress = progress {
          progress(count)
        }
      }
    }
  }

  func upload(
    from localURL: URL, to remotePath: String, mode: mode_t = 0,
  ) async throws {
    guard let fp = try? FileHandle(forReadingFrom: localURL) else {
      throw SFTPClientError.openFileForReadFailed
    }
    defer { try? fp.close() }

    try await withSftpFile(atPath: remotePath, accessType: .writeOnly, mode: mode) { file in
      while true {
        guard let data = try fp.read(upToCount: 102400) else {
          break
        }

        let bytesWritten = try await file.write(data: data)
        if bytesWritten != data.count {
          throw SFTPClientError.oops
        }
      }
    }
  }
}
