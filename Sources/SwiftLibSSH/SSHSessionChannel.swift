import Foundation

public struct SSHChannelData: Sendable, AsyncSequence {
  private let channel: SSHSessionChannel
  private let stream: StreamType
  private let length: Int

  init(channel: SSHSessionChannel, stream: StreamType, length: Int) {
    self.channel = channel
    self.stream = stream
    self.length = length
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(channel: channel, stream: stream, length: length)
  }

  public class Iterator: AsyncIteratorProtocol {
    private let channel: SSHSessionChannel
    private let stream: StreamType
    private let length: Int
    private var buffer: Data

    init(channel: SSHSessionChannel, stream: StreamType, length: Int) {
      self.channel = channel
      self.stream = stream
      self.length = length
      self.buffer = Data(count: length)
    }

    public func next() async throws -> Data? {
      if Task.isCancelled {
        return nil
      }

      return try await channel.read(into: &buffer, length: length, stream: stream)
    }
  }
}

public struct SSHSessionChannel: Sendable {
  private let session: SSHSession
  private let id: SSHChannelID

  init(session: SSHSession, id: SSHChannelID) {
    self.session = session
    self.id = id
  }

  public func close() async {
    await session.closeChannel(id: id)
  }

  public func execute(command: String) async throws {
    try await session.execute(onChannel: id, command: command)
  }

  public func exitStatus() async throws -> SSHExitStatus {
    try await session.exitState(onChannel: id)
  }

  func read(into buffer: inout Data, length: Int, stream: StreamType) async throws -> Data? {
    let bytesRead = try await session.readChannel(
      id: id, into: &buffer, length: length, stream: stream)
    return bytesRead == 0 ? nil : buffer.prefix(bytesRead)
  }

  public func read(from: StreamType) async throws -> Data {
    var output = Data()
    for try await data in stream(from: from) {
      output.append(data)
    }
    return output
  }

  public func stream(from: StreamType, length: Int = 1248) -> SSHChannelData {
    return SSHChannelData(channel: self, stream: from, length: length)
  }
}
