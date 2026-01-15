import Foundation
import Testing

@testable import SwiftLibSSH

func connect() async throws -> SSHSession {
  let session = try SSHSession()
  try await session.setHost("localhost")
  try await session.setPort(2222)
  try await session.connect()
  try await session.authenticate(user: "myuser", password: "mypass")
  #expect(await session.isConnected)
  return session
}

struct LibSSHTests {
  @Test func testPartialReadOfChannel() async throws {
    let bs = 512
    let count = 1_000_000
    let expected = bs * count

    let session = try await connect()

    let actual = try await session.withSessionChannel { channel in
      try await channel.execute(
        command: "dd if=/dev/urandom bs=\(bs) count=\(count) of=/dev/stdout")

      let task = Task {
        let stream = channel.stream(from: .stdout)
        var result = 0
        let iterator = stream.makeAsyncIterator()
        while let data = try await iterator.next() {
          result += data.count
        }
        return result
      }
      try await Task.sleep(nanoseconds: 10_000_000)
      task.cancel()
      return try await task.value
    }

    #expect(actual > 0)
    #expect(actual < expected)

    await session.disconnect()
    await session.free()
  }
}
