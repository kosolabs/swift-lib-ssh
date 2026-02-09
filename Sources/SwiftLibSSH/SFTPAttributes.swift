import CLibSSH
import Foundation

public struct SFTPAttributes: Sendable {
  public enum `Type`: Sendable {
    case regular
    case directory
    case symlink
    case special
    case unknown

    init(from: UInt8) {
      switch Int32(from) {
      case SSH_FILEXFER_TYPE_REGULAR:
        self = .regular
      case SSH_FILEXFER_TYPE_DIRECTORY:
        self = .directory
      case SSH_FILEXFER_TYPE_SYMLINK:
        self = .symlink
      case SSH_FILEXFER_TYPE_SPECIAL:
        self = .special
      default:
        self = .unknown
      }
    }
  }

  public let name: String
  public let flags: UInt32
  public let type: Type
  public let size: UInt64
  public let uid: UInt32
  public let gid: UInt32
  public let owner: String
  public let group: String
  public let permissions: UInt32
  public let accessTime: Date
  public let accessTimeNanos: UInt32
  public let createTime: Date
  public let createTimeNanos: UInt32
  public let modifyTime: Date
  public let modifyTimeNanos: UInt32
  public let extendedCount: UInt32

  private static func string(from cString: UnsafePointer<CChar>?) -> String {
    guard let cString else { return "" }
    return String(cString: cString, encoding: .utf8) ?? ""
  }

  static func from(raw: sftp_attributes_struct) -> SFTPAttributes {
    SFTPAttributes(
      name: string(from: raw.name),
      flags: raw.flags,
      type: .init(from: raw.type),
      size: raw.size,
      uid: raw.uid,
      gid: raw.gid,
      owner: string(from: raw.owner),
      group: string(from: raw.group),
      permissions: raw.permissions,
      accessTime: Date(timeIntervalSince1970: TimeInterval(raw.atime)),
      accessTimeNanos: raw.atime_nseconds,
      createTime: Date(timeIntervalSince1970: TimeInterval(raw.createtime)),
      createTimeNanos: raw.createtime_nseconds,
      modifyTime: Date(timeIntervalSince1970: TimeInterval(raw.mtime)),
      modifyTimeNanos: raw.mtime_nseconds,
      extendedCount: raw.extended_count,
    )
  }
}
