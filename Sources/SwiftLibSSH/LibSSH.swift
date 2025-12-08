import CLibSSH
import Foundation

struct SSHKeyHandle: @unchecked Sendable {
  let key: ssh_key
}

final class SSHKey: @unchecked Sendable {
  let session: SSHSession
  let handle: SSHKeyHandle

  init(session: SSHSession, key: ssh_key) {
    self.session = session
    self.handle = SSHKeyHandle(key: key)
  }

  deinit {
    let handle = self.handle
    let session: SSHSession = self.session
    Task {
      await session.keyFree(handle.key)
    }
  }

  var key: ssh_key {
    handle.key
  }
}

struct SSHChannelHandle: @unchecked Sendable {
  let channel: ssh_channel
}

final class SSHChannel: @unchecked Sendable {
  let session: SSHSession
  let handle: SSHChannelHandle

  init(session: SSHSession, channel: ssh_channel) throws {
    self.session = session
    self.handle = SSHChannelHandle(channel: channel)
  }

  deinit {
    let handle = self.handle
    let session = self.session
    Task {
      await session.channelFree(handle.channel)
    }
  }

  var channel: ssh_channel {
    handle.channel
  }

  func openSession() async throws {
    try await session.channelOpenSession(channel)
  }

  func requestExec(_ command: String) async throws {
    try await session.channelRequestExec(channel, command)
  }

  func read(bufferSize: Int = 1024) async throws -> Data {
    try await session.channelRead(channel, bufferSize: bufferSize)
  }

  func close() async {
    await session.channelClose(channel)
  }
}

enum SSHError: Error {
  case newFailed
  case optionsSetFailed(String)
  case userauthAgentFailed(String)
  case userauthPasswordFailed(String)
  case userauthPublickeyFailed(String)
  case pkiImportPrivkeyFile(String)
  case connectFailed(String)
  case channelNewFailed
  case channelReadFailed(String)
  case channelOpenSessionFailed(String)
  case channelRequestExecFailed(String)
}

struct SSHSessionHandle: @unchecked Sendable {
  let session: ssh_session
}

final actor SSHSession {
  let handle: SSHSessionHandle

  init() throws {
    guard let session: ssh_session = ssh_new() else {
      throw SSHError.newFailed
    }
    self.handle = SSHSessionHandle(session: session)
  }

  deinit {
    ssh_disconnect(handle.session)
    ssh_free(handle.session)
  }

  var session: ssh_session {
    handle.session
  }

  // MARK: - Helper

  private func getError() -> String {
    String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
  }

  // MARK: - Session Operations

  func optionsSet(_ option: ssh_options_e, _ value: UnsafeRawPointer) throws {
    guard ssh_options_set(session, option, value) == SSH_OK else {
      throw SSHError.optionsSetFailed(getError())
    }
  }

  func setHost(_ host: String) throws {
    try optionsSet(SSH_OPTIONS_HOST, host)
  }

  func setPort(_ port: UInt32) throws {
    var port = port
    try optionsSet(SSH_OPTIONS_PORT, &port)
  }

  func connect() throws {
    guard ssh_connect(session) == SSH_OK else {
      throw SSHError.connectFailed(getError())
    }
  }

  func userauthAgent(_ user: String) throws {
    guard ssh_userauth_agent(session, user) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHError.userauthAgentFailed(getError())
    }
  }

  func userauthPassword(_ user: String, _ password: String) throws {
    guard ssh_userauth_password(session, user, password) == SSH_AUTH_SUCCESS.rawValue else {
      throw SSHError.userauthPasswordFailed(getError())
    }
  }

  func userauthPublickey(_ user: String, _ privateKey: SSHKey) throws {
    guard ssh_userauth_publickey(session, user, privateKey.key) == SSH_AUTH_SUCCESS.rawValue
    else {
      throw SSHError.userauthPublickeyFailed(getError())
    }
  }

  func isConnected() -> Bool {
    ssh_is_connected(session) == 1
  }

  func disconnect() {
    ssh_disconnect(session)
  }

  // MARK: - Key Operations

  func pkiImportPrivkeyFile(_ privateKeyPath: String, _ passphrase: String? = nil) throws -> SSHKey
  {
    var key: ssh_key?
    guard ssh_pki_import_privkey_file(privateKeyPath, passphrase, nil, nil, &key) == SSH_OK
    else {
      throw SSHError.pkiImportPrivkeyFile(getError())
    }

    return SSHKey(session: self, key: key!)
  }

  func keyFree(_ key: ssh_key) {
    ssh_key_free(key)
  }

  // MARK: - Channel Operations

  func channelNew() throws -> SSHChannel {
    guard let channel = ssh_channel_new(session) else {
      throw SSHError.newFailed
    }
    return try SSHChannel(session: self, channel: channel)
  }

  func channelClose(_ channel: ssh_channel) {
    _ = ssh_channel_close(channel)
  }

  func channelFree(_ channel: ssh_channel) {
    ssh_channel_free(channel)
  }

  func channelOpenSession(_ channel: ssh_channel) throws {
    guard ssh_channel_open_session(channel) == SSH_OK else {
      throw SSHError.channelOpenSessionFailed(getError())
    }
  }

  func channelRequestExec(_ channel: ssh_channel, _ command: String) throws {
    guard ssh_channel_request_exec(channel, command) == SSH_OK else {
      throw SSHError.channelRequestExecFailed(getError())
    }
  }

  func channelRead(_ channel: ssh_channel, bufferSize: Int = 1024) throws -> Data {
    var buffer = [CChar](repeating: 0, count: bufferSize)
    let bytesRead = ssh_channel_read(channel, &buffer, UInt32(bufferSize), 0)

    if bytesRead < 0 {
      throw SSHError.channelReadFailed(getError())
    }

    return Data(bytes: buffer, count: Int(bytesRead))
  }
}
