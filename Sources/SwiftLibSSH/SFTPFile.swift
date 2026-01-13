import Foundation

public enum SFTPFileError: Error {
  case createFileFailed
  case openFileForReadFailed
  case openFileForWriteFailed
  case oops
}

public struct SFTPStream: Sendable, AsyncSequence {
  private let file: SFTPFile
  private let offset: UInt64
  private let length: UInt64

  init(file: SFTPFile, offset: UInt64, length: UInt64) {
    self.file = file
    self.offset = offset
    self.length = length
  }

  public class SFTPStreamDataIterator: AsyncIteratorProtocol {
    static let QueueSize: Int = 16

    private let file: SFTPFile
    private let offset: UInt64
    private let length: UInt64

    private var count: UInt64 = 0
    private var buffer: Data = Data(count: 102400)
    private var queue: [SFTPAio] = []

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

      while queue.count < SFTPStreamDataIterator.QueueSize && count < length {
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

  public func makeAsyncIterator() -> SFTPStreamDataIterator {
    SFTPStreamDataIterator(file: file, offset: offset, length: length)
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

  func seek(offset: UInt64) async throws {
    try await session.seekFile(id: id, offset: offset)
  }

  func beginRead(length: Int) async throws -> SFTPAio {
    try await session.beginRead(id: id, length: length)
  }

  public func read(offset: UInt64 = 0, length: UInt64 = UInt64.max) async throws -> Data {
    try await seek(offset: offset)
    var result = Data()
    let bufferSize = 102400
    var buffer = Data(count: bufferSize)
    while result.count < length {
      let bytesToRead = Int(min(UInt64(bufferSize), length - UInt64(result.count)))
      let bytesRead = try await session.readFile(id: id, into: &buffer, length: bytesToRead)
      guard bytesRead > 0 else { break }
      result.append(buffer.prefix(bytesRead))
    }
    return result
  }

  public func write(data: Data) async throws -> Int {
    try await session.writeFile(id: id, data: data)
  }

  public func stream(offset: UInt64 = 0, length: UInt64 = UInt64.max) -> SFTPStream {
    return SFTPStream(file: self, offset: offset, length: length)
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
