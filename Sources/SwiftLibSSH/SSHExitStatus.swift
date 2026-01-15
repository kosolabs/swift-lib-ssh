public struct SSHExitStatus: Sendable {
  let code: UInt8?
  let signal: String?
  let coreDumped: Bool

  static func from(
    code: Int32, signal: UnsafeMutablePointer<CChar>?, coreDumped: Int32
  ) -> SSHExitStatus {
    return SSHExitStatus(
      code: code == -1 ? nil : UInt8(code),
      signal: signal.map({ s in String(cString: s) }),
      coreDumped: coreDumped != 0)
  }
}
