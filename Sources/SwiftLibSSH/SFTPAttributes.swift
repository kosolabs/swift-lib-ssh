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

  let name: String?
  let longname: String?
  let flags: UInt32
  let type: Type
  let size: UInt64
  let uid: UInt32
  let gid: UInt32
  let owner: String?
  let group: String?
  let permissions: UInt32
  let atime64: UInt64
  let atime: UInt32
  let atime_nseconds: UInt32
  let createtime: UInt64
  let createtime_nseconds: UInt32
  let mtime64: UInt64
  let mtime: UInt32
  let mtime_nseconds: UInt32
  let extended_count: UInt32

  private static func string(from cString: UnsafePointer<CChar>?) -> String? {
    guard let cString else { return nil }
    return String(cString: cString, encoding: .utf8)
  }

  static func from(raw: sftp_attributes_struct) -> SFTPAttributes {
    SFTPAttributes(
      name: string(from: raw.name),
      longname: string(from: raw.longname),
      flags: raw.flags,
      type: .init(from: raw.type),
      size: raw.size,
      uid: raw.uid,
      gid: raw.gid,
      owner: string(from: raw.owner),
      group: string(from: raw.group),
      permissions: raw.permissions,
      atime64: raw.atime64,
      atime: raw.atime,
      atime_nseconds: raw.atime_nseconds,
      createtime: raw.createtime,
      createtime_nseconds: raw.createtime_nseconds,
      mtime64: raw.mtime64,
      mtime: raw.mtime,
      mtime_nseconds: raw.mtime_nseconds,
      extended_count: raw.extended_count
    )
  }
}
