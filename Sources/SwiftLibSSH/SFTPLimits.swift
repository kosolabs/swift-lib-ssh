import CLibSSH
import Foundation

public struct SFTPLimits: Codable, Sendable {
  public static let defaultBufferSize: UInt64 = 102400

  public let maxOpenHandles: UInt64
  public let maxPacketLength: UInt64
  public let maxReadLength: UInt64
  public let maxWriteLength: UInt64

  public func writeLength(for bufferSize: UInt64 = defaultBufferSize) -> UInt64 {
    min(bufferSize, maxWriteLength)
  }

  public func readLength(for bufferSize: UInt64 = defaultBufferSize) -> UInt64 {
    min(bufferSize, maxReadLength)
  }

  static func from(raw: sftp_limits_struct) -> SFTPLimits {
    SFTPLimits(
      maxOpenHandles: raw.max_open_handles,
      maxPacketLength: raw.max_packet_length,
      maxReadLength: raw.max_read_length,
      maxWriteLength: raw.max_write_length
    )
  }
}
