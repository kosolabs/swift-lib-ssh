import Foundation

public struct SSHChannelData: Sendable, AsyncSequence {
  private let channel: SSHChannel
  private let bufferSize: Int

  init(channel: SSHChannel, bufferSize: Int) {
    self.channel = channel
    self.bufferSize = bufferSize
  }

  public struct SSHChannelDataIterator: AsyncIteratorProtocol {
    private let channel: SSHChannel
    private var buffer: [UInt8]

    init(channel: SSHChannel, bufferSize: Int) {
      self.channel = channel
      self.buffer = [UInt8](repeating: 0, count: bufferSize)
    }

    public mutating func next() async throws -> Data? {
      if Task.isCancelled {
        return nil
      }
      return try await channel.read(into: &buffer)
    }
  }

  public func makeAsyncIterator() -> SSHChannelDataIterator {
    SSHChannelDataIterator(channel: channel, bufferSize: bufferSize)
  }
}

public struct SSHChannel: Sendable {
  private let session: SSHSession
  private let id: UUID

  init(session: SSHSession, id: UUID) {
    self.session = session
    self.id = id
  }

  public func free() async {
    await session.freeChannel(id: id)
  }

  public func withOpenedSession<T: Sendable>(
    perform body: @Sendable () async throws -> T
  ) async throws -> T {
    try await session.withOpenedChannelSession(id: id, perform: body)
  }

  public func openSession() async throws {
    try await session.openChannelSession(id: id)
  }

  public func close() async {
    await session.closeChannel(id: id)
  }

  public func execute(command: String) async throws {
    try await session.execute(onChannel: id, command: command)
  }

  public func read(into buffer: inout [UInt8]) async throws -> Data? {
    try await session.readChannel(id: id, into: &buffer)
  }

  public func read(maxBytes: Int = 1248) async throws -> Data? {
    var buffer = [UInt8](repeating: 0, count: maxBytes)
    return try await read(into: &buffer)
  }

  public func stream(maxBytes: Int = 1248) -> SSHChannelData {
    return SSHChannelData(channel: self, bufferSize: maxBytes)
  }
}
