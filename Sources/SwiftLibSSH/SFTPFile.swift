import Foundation

public struct SFTPStream: Sendable, AsyncSequence {
  private let file: SFTPFile
  private let bufferSize: Int

  init(file: SFTPFile, bufferSize: Int) {
    self.file = file
    self.bufferSize = bufferSize
  }

  public struct SFTPStreamDataIterator: AsyncIteratorProtocol {
    private let file: SFTPFile
    private var buffer: [UInt8]

    init(file: SFTPFile, bufferSize: Int) {
      self.file = file
      self.buffer = [UInt8](repeating: 0, count: bufferSize)
    }

    public mutating func next() async throws -> Data? {
      if Task.isCancelled {
        return nil
      }
      return try await file.read(into: &buffer)
    }
  }

  public func makeAsyncIterator() -> SFTPStreamDataIterator {
    SFTPStreamDataIterator(file: file, bufferSize: bufferSize)
  }
}

public struct SFTPFile: Sendable {
  private let session: SSHSession
  private let id: UUID

  init(session: SSHSession, id: UUID) {
    self.session = session
    self.id = id
  }

  public func close() async {
    await session.closeFile(id: id)
  }

  public func seek(offset: UInt64) async throws {
    try await session.seekFile(id: id, offset: offset)
  }

  public func read(into buffer: inout [UInt8]) async throws -> Data? {
    try await session.readFile(id: id, into: &buffer)
  }

  public func read(maxBytes: Int = 102400) async throws -> Data? {
    var buffer = [UInt8](repeating: 0, count: maxBytes)
    return try await read(into: &buffer)
  }

  public func stream(maxBytes: Int = 102400) -> SFTPStream {
    return SFTPStream(file: self, bufferSize: maxBytes)
  }
}
