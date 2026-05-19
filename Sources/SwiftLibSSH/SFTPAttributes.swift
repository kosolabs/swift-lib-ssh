import CLibSSH
import Foundation

public struct SFTPAttributes: Codable, Sendable {
  public struct Flags: OptionSet, Codable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let size =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_SIZE))
    public static let uidGid =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_UIDGID))
    public static let permissions =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_PERMISSIONS))
    public static let accessTime =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_ACCESSTIME))
    public static let createTime =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_CREATETIME))
    public static let modifyTime =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_MODIFYTIME))
    public static let ownerGroup =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_OWNERGROUP))
    public static let subsecondTimes =
      Flags(rawValue: UInt32(bitPattern: SSH_FILEXFER_ATTR_SUBSECOND_TIMES))
  }

  public enum FileType: Codable, Sendable {
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
  public let type: FileType
  public let size: UInt64?
  public let uid: UInt32?
  public let gid: UInt32?
  public let owner: String?
  public let group: String?
  public let permissions: UInt32?
  public let accessTime: Date?
  public let accessTimeNanos: UInt32?
  public let createTime: Date?
  public let createTimeNanos: UInt32?
  public let modifyTime: Date?
  public let modifyTimeNanos: UInt32?
  public let extendedCount: UInt32

  private static func string(from cString: UnsafePointer<CChar>?) -> String? {
    guard let cString else { return nil }
    return String(cString: cString, encoding: .utf8)
  }

  public init(
    name: String? = nil,
    type: FileType = .unknown,
    size: UInt64? = nil,
    uid: UInt32? = nil,
    gid: UInt32? = nil,
    owner: String? = nil,
    group: String? = nil,
    permissions: UInt32? = nil,
    accessTime: Date? = nil,
    accessTimeNanos: UInt32? = nil,
    createTime: Date? = nil,
    createTimeNanos: UInt32? = nil,
    modifyTime: Date? = nil,
    modifyTimeNanos: UInt32? = nil,
    extendedCount: UInt32 = 0
  ) {
    self.name = name
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
    let flags = Flags(rawValue: raw.flags)
    let hasNanos = flags.contains(.subsecondTimes)
    return SFTPAttributes(
      name: string(from: raw.name),
      type: .init(from: raw.type),
      size: flags.contains(.size) ? raw.size : nil,
      uid: flags.contains(.uidGid) ? raw.uid : nil,
      gid: flags.contains(.uidGid) ? raw.gid : nil,
      owner: flags.contains(.ownerGroup) ? string(from: raw.owner) : nil,
      group: flags.contains(.ownerGroup) ? string(from: raw.group) : nil,
      permissions: flags.contains(.permissions) ? raw.permissions : nil,
      accessTime: flags.contains(.accessTime)
        ? Date(timeIntervalSince1970: TimeInterval(raw.atime)) : nil,
      accessTimeNanos: hasNanos && flags.contains(.accessTime)
        ? raw.atime_nseconds : nil,
      createTime: flags.contains(.createTime)
        ? Date(timeIntervalSince1970: TimeInterval(raw.createtime)) : nil,
      createTimeNanos: hasNanos && flags.contains(.createTime)
        ? raw.createtime_nseconds : nil,
      modifyTime: (flags.contains(.modifyTime) || flags.contains(.accessTime))
        ? Date(timeIntervalSince1970: TimeInterval(raw.mtime)) : nil,
      modifyTimeNanos: hasNanos && (flags.contains(.modifyTime) || flags.contains(.accessTime))
        ? raw.mtime_nseconds : nil,
      extendedCount: raw.extended_count,
    )
  }
}
