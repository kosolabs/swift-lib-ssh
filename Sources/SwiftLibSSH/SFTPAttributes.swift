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

  public let name: String?
  // TODO: Decode flags as bools
  public let flags: UInt32
  public let type: Type
  public let size: UInt64
  public let uid: UInt32
  public let gid: UInt32
  public let owner: String?
  public let group: String?
  public let permissions: UInt32
  public let accessTime: Date
  public let accessTimeNanos: UInt32
  public let createTime: Date
  public let createTimeNanos: UInt32
  public let modifyTime: Date
  public let modifyTimeNanos: UInt32
  public let extendedCount: UInt32

  private static func string(from cString: UnsafePointer<CChar>?) -> String? {
    guard let cString else { return nil }
    return String(cString: cString, encoding: .utf8)
  }

  public init(
    name: String? = nil,
    flags: UInt32 = 0,
    type: Type = .unknown,
    size: UInt64 = 0,
    uid: UInt32 = 0,
    gid: UInt32 = 0,
    owner: String? = nil,
    group: String? = nil,
    permissions: UInt32 = 0,
    accessTime: Date = Date(timeIntervalSince1970: 0),
    accessTimeNanos: UInt32 = 0,
    createTime: Date = Date(timeIntervalSince1970: 0),
    createTimeNanos: UInt32 = 0,
    modifyTime: Date = Date(timeIntervalSince1970: 0),
    modifyTimeNanos: UInt32 = 0,
    extendedCount: UInt32 = 0
  ) {
    self.name = name
    self.flags = flags
    self.type = type
    self.size = size
    self.uid = uid
    self.gid = gid
    self.owner = owner
    self.group = group
    self.permissions = permissions
    self.accessTime = accessTime
    self.accessTimeNanos = accessTimeNanos
    self.createTime = createTime
    self.createTimeNanos = createTimeNanos
    self.modifyTime = modifyTime
    self.modifyTimeNanos = modifyTimeNanos
    self.extendedCount = extendedCount
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
