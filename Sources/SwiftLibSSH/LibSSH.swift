import CLibSSH
import Foundation

enum SSHKeyError: Error {
  case pkiImportPrivkeyFile(String)
}

final class SSHKey {
  var key: ssh_key?

  init(session: SSHSession, privateKeyPath: String, passphrase: String? = nil) throws {
    guard ssh_pki_import_privkey_file(privateKeyPath, passphrase, nil, nil, &key) == SSH_OK
    else {
      throw SSHKeyError.pkiImportPrivkeyFile(session.getError())
    }
  }

  deinit {
    ssh_key_free(key)
  }
}

enum SSHChannelError: Error {
  case newFailed
  case readFailed(String)
  case openSessionFailed(String)
  case requestExecFailed(String)
}

final class SSHChannel: @unchecked Sendable {
  let session: SSHSession
  let channel: ssh_channel
  var buffer: [CChar]

  init(session: SSHSession, bufferSize: Int) throws {
    self.session = session
    guard let channel = ssh_channel_new(session.session) else {
      throw SSHChannelError.newFailed
    }
    self.channel = channel
    self.buffer = [CChar](repeating: 0, count: bufferSize)
  }

  deinit {
    ssh_channel_free(channel)
  }

  func openSession() async throws {
    try session.queue.sync {
      guard ssh_channel_open_session(channel) == SSH_OK else {
        throw SSHChannelError.openSessionFailed(session.getError())
      }
    }
  }

  func requestExec(_ command: String) async throws {
    try session.queue.sync {
      guard ssh_channel_request_exec(channel, command) == SSH_OK else {
        throw SSHChannelError.requestExecFailed(session.getError())
      }
    }
  }

  func read() async throws -> Data {
    return try await withCheckedThrowingContinuation { continuation in
      session.queue.async {
        let bytesRead = ssh_channel_read(self.channel, &self.buffer, UInt32(self.buffer.count), 0)
        if bytesRead < 0 {
          continuation.resume(throwing: SSHChannelError.readFailed(self.session.getError()))
        } else {
          continuation.resume(returning: Data(bytes: self.buffer, count: Int(bytesRead)))
        }
      }
    }
  }

  func close() {
    session.queue.sync {
      _ = ssh_channel_close(channel)
    }
  }
}

enum SSHSessionError: Error {
  case newFailed
  case optionsSetFailed(String)
  case userauthAgentFailed(String)
  case userauthPasswordFailed(String)
  case userauthPublickeyFailed(String)
  case connectFailed(String)
}

final class SSHSession: @unchecked Sendable {
  let session: ssh_session
  let queue: DispatchQueue

  init() throws {
    guard let session: ssh_session = ssh_new() else {
      throw SSHSessionError.newFailed
    }
    self.session = session
    self.queue = DispatchQueue(label: "com.kosolabs.SwiftLibSSH", qos: .userInitiated)
  }

  deinit {
    queue.sync {
      ssh_disconnect(session)
      ssh_free(session)
    }
  }

  func optionsSet(_ option: ssh_options_e, _ value: UnsafeRawPointer) async throws {
    try queue.sync {
      guard ssh_options_set(session, option, value) == SSH_OK else {
        throw SSHSessionError.optionsSetFailed(getError())
      }
    }
  }

  func setHost(_ host: String) async throws {
    try await optionsSet(SSH_OPTIONS_HOST, host)
  }

  func setPort(_ port: UInt32) async throws {
    var port = port
    try await optionsSet(SSH_OPTIONS_PORT, &port)
  }

  func connect() async throws {
    try queue.sync {
      guard ssh_connect(session) == SSH_OK else {
        throw SSHSessionError.connectFailed(getError())
      }
    }
  }

  func userauthAgent(_ user: String) async throws {
    try queue.sync {
      guard ssh_userauth_agent(session, user) == SSH_AUTH_SUCCESS.rawValue else {
        throw SSHSessionError.userauthAgentFailed(getError())
      }
    }
  }

  func userauthPassword(_ user: String, _ password: String) async throws {
    try queue.sync {
      guard ssh_userauth_password(session, user, password) == SSH_AUTH_SUCCESS.rawValue else {
        throw SSHSessionError.userauthPasswordFailed(getError())
      }
    }
  }

  func userauthPublickey(_ user: String, _ privateKey: SSHKey) async throws {
    try queue.sync {
      guard ssh_userauth_publickey(session, user, privateKey.key) == SSH_AUTH_SUCCESS.rawValue
      else {
        throw SSHSessionError.userauthPublickeyFailed(getError())
      }
    }
  }

  func isConnected() -> Bool {
    queue.sync {
      return ssh_is_connected(session) == 1
    }
  }

  func disconnect() {
    queue.sync {
      ssh_disconnect(session)
    }
  }

  func getError() -> String {
    queue.sync {
      return String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
    }
  }

  func pkiImportPrivkeyFile(_ privateKeyPath: String, _ passphrase: String? = nil) throws -> SSHKey
  {
    return try SSHKey(session: self, privateKeyPath: privateKeyPath, passphrase: passphrase)
  }

  func newChannel(bufferSize: Int = 1024) throws -> SSHChannel {
    return try SSHChannel(session: self, bufferSize: bufferSize)
  }
}
