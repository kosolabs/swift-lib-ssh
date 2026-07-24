public struct SSHExitStatus: Codable, Sendable {
  public let code: UInt8?
  public let signal: String?
  public let coreDumped: Bool

  static func from(
    code: Int32, signal: UnsafeMutablePointer<CChar>?, coreDumped: Int32
  ) -> SSHExitStatus {
    return SSHExitStatus(
      code: code == -1 ? nil : UInt8(code),
      signal: signal.map({ s in String(cString: s) }),
      coreDumped: coreDumped != 0)
  }
}
