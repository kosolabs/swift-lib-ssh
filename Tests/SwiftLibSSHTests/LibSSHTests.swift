import Foundation
import Testing

@testable import SwiftLibSSH

enum TestError: Error {
  case noData
}

struct LibSSHTests {
  @Test func testPartialReadOfChannel() async throws {
    let bs = 512
    let count = 1_000_000
    let expected = bs * count

    let session = try SSHSession()
    try await session.setHost("localhost")
    try await session.setPort(2222)
    try await session.connect()
    try await session.authenticate(user: "myuser", password: "mypass")
    #expect(await session.isConnected)

    let actual = try await session.withChannel { channel in
      try await channel.withOpenedSession {
        try await channel.execute(
          command: "dd if=/dev/urandom bs=\(bs) count=\(count) of=/dev/stdout")

        let task = Task {
          let stream = channel.stream()
          var result = 0
          var iterator = stream.makeAsyncIterator()
          while let data = try await iterator.next() {
            result += data.count
          }
          return result
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        return try await task.value
      }
    }

    #expect(actual > 0)
    #expect(actual < expected)

    await session.disconnect()
    await session.free()
  }

  @Test func testCancellationOfForAwaitLoopOverChannelStream() async throws {
    let expected = 1_000_000
    let session = try SSHSession()
    try await session.setHost("localhost")
    try await session.setPort(2222)
    try await session.connect()
    try await session.authenticate(user: "myuser", password: "mypass")
    #expect(await session.isConnected)

    let actual = try await session.withChannel { channel in
      try await channel.withOpenedSession {
        try await channel.execute(
          command: "dd if=/dev/urandom bs=\(expected) count=1 of=/dev/stdout")

        for try await data: Data in channel.stream() {
          // Returning here causes stream to cancel
          return data
        }

        throw TestError.noData
      }
    }

    #expect(actual.count > 0)
    #expect(actual.count < expected)

    await session.disconnect()
    await session.free()
  }
}
