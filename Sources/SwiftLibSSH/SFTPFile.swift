import Foundation

public enum SFTPFileError: Error {
  case createFileFailed
  case openFileForReadFailed
  case openFileForWriteFailed
  case oops
}

public struct SFTPStream: Sendable, AsyncSequence {
  private let file: SFTPFile
  private let count: Int

  init(file: SFTPFile, count: Int) {
    self.file = file
    self.count = count
  }

  public class SFTPStreamDataIterator: AsyncIteratorProtocol {
    static let QueueSize: Int = 16

    private let file: SFTPFile
    private let count: Int
    private var buffer: Data
    private var queue: [SFTPAio] = []

    init(file: SFTPFile, count: Int) {
      self.file = file
      self.count = count
      self.buffer = Data(count: count)
    }

    public func next() async throws -> Data? {
      if Task.isCancelled {
        return nil
      }

      while queue.count < SFTPStreamDataIterator.QueueSize {
        let aio = try await file.beginRead(count: count)
        queue.append(aio)
      }
      let aio = queue.removeFirst()
      try await aio.read(into: &buffer, count: count)
      if buffer.count == 0 {
        while !queue.isEmpty {
          await queue.removeFirst().free()
        }
        return nil
      }
      return buffer
    }
  }

  public func makeAsyncIterator() -> SFTPStreamDataIterator {
    SFTPStreamDataIterator(file: file, count: count)
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

  public func read(into buffer: inout Data, count: Int) async throws {
    try await session.readFile(id: id, into: &buffer, count: count)
  }

  public func read(count: Int = 102400) async throws -> Data? {
    var buffer = Data(count: count)
    try await read(into: &buffer, count: count)
    if buffer.isEmpty { return nil }
    return buffer
  }

  public func write(data: Data) async throws -> Int {
    try await session.writeFile(id: id, data: data)
  }

  public func beginRead(count: Int) async throws -> SFTPAio {
    try await session.beginRead(id: id, count: count)
  }

  public func stream(count: Int = 102400) -> SFTPStream {
    return SFTPStream(file: self, count: count)
  }

  public func download(
    to localURL: URL,
    progress: (@Sendable (UInt64) -> Void)? = nil
  ) async throws {
    if !FileManager.default.createFile(atPath: localURL.path, contents: nil) {
      throw SFTPFileError.createFileFailed
    }

    guard let fp = try? FileHandle(forWritingTo: localURL) else {
      throw SFTPFileError.openFileForWriteFailed
    }
    defer { try? fp.close() }

    var count: UInt64 = 0
    for try await data in stream() {
      try fp.write(contentsOf: data)
      count += UInt64(data.count)
      progress?(count)
    }
  }

  public func upload(
    from localURL: URL, mode: mode_t = 0,
    progress: (@Sendable (UInt64) -> Void)? = nil
  ) async throws {
    guard let fp = try? FileHandle(forReadingFrom: localURL) else {
      throw SFTPFileError.openFileForReadFailed
    }
    defer { try? fp.close() }

    var count: UInt64 = 0
    while true {
      guard let data = try fp.read(upToCount: 102400) else {
        break
      }

      let bytesWritten = try await write(data: data)
      if bytesWritten != data.count {
        throw SFTPFileError.oops
      }
      count += UInt64(data.count)
      progress?(count)
    }
  }
}
