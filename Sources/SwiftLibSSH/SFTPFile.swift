import Foundation

public struct SFTPStream: Sendable, AsyncSequence {
  private let file: SFTPFile
  private let bufferSize: Int
  private let queueSize: Int

  init(file: SFTPFile, bufferSize: Int, queueSize: Int) {
    self.file = file
    self.bufferSize = bufferSize
    self.queueSize = queueSize
  }

  public class SFTPStreamDataIterator: AsyncIteratorProtocol {
    private let file: SFTPFile
    private var buffer: [UInt8]
    private let queueSize: Int
    private var queue: [SFTPAio] = []

    init(file: SFTPFile, bufferSize: Int, queueSize: Int) {
      self.file = file
      self.buffer = [UInt8](repeating: 0, count: bufferSize)
      self.queueSize = queueSize
    }

    public func next() async throws -> Data? {
      if Task.isCancelled {
        return nil
      }

      while queue.count < queueSize {
        let aio = try await file.beginRead(bufferSize: buffer.count)
        queue.append(aio)
      }
      let aio = queue.removeFirst()
      let result = try await aio.read(into: &buffer)
      if result == nil {
        while !queue.isEmpty {
          await queue.removeFirst().free()
        }
      }
      return result
    }
  }

  public func makeAsyncIterator() -> SFTPStreamDataIterator {
    SFTPStreamDataIterator(file: file, bufferSize: bufferSize, queueSize: queueSize)
  }
}

public struct SFTPFile: Sendable {
  private let session: SSHSession
  private let id: SFTPFileID

  init(session: SSHSession, id: SFTPFileID) {
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

  public func write(data: Data) async throws -> Int {
    try await session.writeFile(id: id, data: data)
  }

  public func beginRead(bufferSize: Int) async throws -> SFTPAio {
    try await session.beginRead(id: id, bufferSize: bufferSize)
  }

  public func stream(maxBytes: Int = 102400, queueSize: Int = 16) -> SFTPStream {
    return SFTPStream(file: self, bufferSize: maxBytes, queueSize: queueSize)
  }
}
