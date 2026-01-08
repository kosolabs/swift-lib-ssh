import CLibSSH
import Foundation

public struct SFTPLimits: Sendable {
  let maxOpenHandles: UInt64
  let maxPacketLength: UInt64
  let maxReadLength: UInt64
  let maxWriteLength: UInt64

  static func from(raw: sftp_limits_struct) -> SFTPLimits {
    SFTPLimits(
      maxOpenHandles: raw.max_open_handles,
      maxPacketLength: raw.max_packet_length,
      maxReadLength: raw.max_read_length,
      maxWriteLength: raw.max_write_length
    )
  }
}
