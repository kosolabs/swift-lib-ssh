import ArgumentParser
import Foundation
import SwiftLibSSH
import Synchronization

struct SSHConfig: ParsableArguments {
  @Option(name: .shortAndLong, help: "The user to log in as on the remote machine")
  var loginName: String = ProcessInfo.processInfo.userName

  @Option(name: .shortAndLong, help: "Identity file to use as the private key")
  var identityFile: String

  @Argument(help: "The remote host to connect to")
  var host: String

  func connect() async throws -> (ssh: SSHClient, sftp: SFTPClient) {
    let ssh = try await SSHClient.connect(
      host: host, user: loginName,
      privateKeyURL: URL(fileURLWithPath: identityFile)
    )

    let sftp = try await ssh.sftp()

    return (ssh, sftp)
  }

  func withConnection<T>(_ body: (SSHClient, SFTPClient) async throws -> T) async throws -> T {
    let (ssh, sftp) = try await connect()
    do {
      let result = try await body(ssh, sftp)
      await sftp.close()
      await ssh.close()
      return result
    } catch {
      await sftp.close()
      await ssh.close()
      throw error
    }
  }
}

@main
struct SwiftSSH: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "SwiftLibSSH CLI test tool",
    subcommands: [Upload.self]
  )
}

struct Upload: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Upload a file"
  )

  @OptionGroup var sshConfig: SSHConfig

  @Argument(help: "Source path")
  var source: String

  @Argument(help: "Destination path")
  var destination: String

  @Option(help: "Permissions")
  var mode: mode_t = 0o644

  func run() async throws {
    try await sshConfig.withConnection { ssh, sftp in
      let fp = try FileHandle(forReadingFrom: URL(filePath: source))
      let speedometer = Speedometer(total: try fp.seekToEnd())
      try fp.seek(toOffset: 0)

      try await sftp.withSftpFile(atPath: destination, accessType: .writeOnly, mode: mode) { file in
        try await file.withAsyncWriter { writer in
          while let data = try fp.read(upToCount: 102400) {
            try await writer.write(data: data)
            if let progress = speedometer.update(delta: data.count) {
              print("Uploading \(source): \(progress)")
            }
          }
        }
      }
    }
  }
}
