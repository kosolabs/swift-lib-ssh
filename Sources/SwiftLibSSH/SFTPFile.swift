import Foundation

public enum SFTPFileError: Error {
  case createFileFailed
  case openFileForReadFailed
  case openFileForWriteFailed
  case writeFailed
}

public class SFTPReader: AsyncSequence {
  private let file: SFTPFile
  private let offset: UInt64
  private let length: UInt64

  init(file: SFTPFile, offset: UInt64, length: UInt64) {
    self.file = file
    self.offset = offset
    self.length = length
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(file: file, offset: offset, length: length)
  }

  public class Iterator: AsyncIteratorProtocol {
    static let QueueSize: Int = 16

    private let file: SFTPFile
    private let offset: UInt64
    private let length: UInt64

    private var count: UInt64 = 0
    private var buffer: Data = Data(count: SSHSession.BufferSize)
    private var queue: [SFTPAioReadContext] = []

    init(file: SFTPFile, offset: UInt64, length: UInt64) {
      self.file = file
      self.offset = offset
      self.length = length
    }

    public func next() async throws -> Data? {
      if Task.isCancelled {
        return nil
      }

      if count == 0 {
        try await file.seek(offset: offset)
      }

      while queue.count < Iterator.QueueSize && count < length {
        let size = Swift.min(UInt64(buffer.count), length - count)
        let aio = try await file.beginRead(length: Int(size))
        count += size
        queue.append(aio)
      }

      if queue.isEmpty {
        return nil
      }

      let aio = queue.removeFirst()
      let bytesRead = try await aio.read(into: &buffer)
      return bytesRead == 0 ? nil : buffer.prefix(bytesRead)
    }
  }
}

public class SFTPWriter {
  static let QueueSize: Int = 16

  private let file: SFTPFile
  private var queue: [SFTPAioWriteContext] = []

  init(file: SFTPFile) {
    self.file = file
  }

  public func write(data: Data) async throws {
    while queue.count >= SFTPWriter.QueueSize {
      try await queue.removeFirst().flush()
    }
    let aio = try await file.beginWrite(data: data)
    queue.append(aio)
  }

  public func flush() async throws {
    while !queue.isEmpty {
      try await queue.removeFirst().flush()
    }
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

  public func attributes() async throws -> SFTPAttributes {
    try await session.statFile(id: id)
  }

  func seek(offset: UInt64) async throws {
    try await session.seekFile(id: id, offset: offset)
  }

  public func read(offset: UInt64 = 0, length: UInt64 = UInt64.max) async throws -> Data {
    try await seek(offset: offset)
    var result = Data()
    var buffer = Data(count: SSHSession.BufferSize)
    while result.count < length {
      let bytesToRead = Int(min(UInt64(SSHSession.BufferSize), length - UInt64(result.count)))
      let bytesRead = try await session.readFile(id: id, into: &buffer, length: bytesToRead)
      guard bytesRead > 0 else { break }
      result.append(buffer.prefix(bytesRead))
    }
    return result
  }

  public func write(data: Data) async throws {
    for curr in stride(from: 0, to: data.count, by: SSHSession.BufferSize) {
      let next = min(data.count, curr + SSHSession.BufferSize)
      let buffer = data.subdata(in: curr..<next)
      let bytesWritten = try await session.writeFile(id: id, data: buffer)
      if bytesWritten != buffer.count {
        throw SFTPFileError.writeFailed
      }
    }
  }

  func beginRead(length: Int) async throws -> SFTPAioReadContext {
    try await session.beginRead(id: id, length: length)
  }

  public func stream(offset: UInt64 = 0, length: UInt64 = UInt64.max) -> SFTPReader {
    return SFTPReader(file: self, offset: offset, length: length)
  }

  func beginWrite(data: Data) async throws -> SFTPAioWriteContext {
    try await session.beginWrite(id: id, buffer: data, length: data.count)
  }

  public func withAsyncWriter(
    perform body: (SFTPWriter) async throws -> Void
  ) async throws {
    let writer = SFTPWriter(file: self)
    try await body(writer)
    try await writer.flush()
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
    try await withAsyncWriter { writer in
      while let data = try fp.read(upToCount: SSHSession.BufferSize) {
        try await writer.write(data: data)
        count += UInt64(data.count)
        progress?(count)
      }
    }
  }
}
