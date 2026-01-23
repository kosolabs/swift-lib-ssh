import Foundation
import Testing

@testable import SwiftLibSSH

var host: String {
  let env = ProcessInfo.processInfo.environment
  return env["SWIFT_LIBSSH_TEST_HOST"] ?? "localhost"
}

var port: UInt32 {
  let env = ProcessInfo.processInfo.environment
  if let portString = env["SWIFT_LIBSSH_TEST_PORT"], let port = UInt32(portString) {
    return port
  }
  return 2222
}

var user: String {
  let env = ProcessInfo.processInfo.environment
  return env["SWIFT_LIBSSH_TEST_USER"] ?? "myuser"
}

var password: String {
  let env = ProcessInfo.processInfo.environment
  return env["SWIFT_LIBSSH_TEST_PASSWORD"] ?? "mypass"
}

var privateKey: URL {
  let env = ProcessInfo.processInfo.environment
  return URL(fileURLWithPath: env["SWIFT_LIBSSH_TEST_PRIVATE_KEY_PATH"] ?? "Tests/Data/id_ed25519")
}

func connect() async throws -> SSHSession {
  let session = try SSHSession()
  try await session.setHost(host)
  try await session.setPort(port)
  try await session.connect()
  try await session.authenticate(user: user, password: password)
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
        while !Task.isCancelled, let data = try await iterator.next() {
          result += data.count
        }
        return result
      }
      try await Task.sleep(nanoseconds: 100_000)
      task.cancel()
      return try await task.value
    }

    #expect(actual > 0)
    #expect(actual < expected)

    await session.disconnect()
    await session.free()
  }
}
