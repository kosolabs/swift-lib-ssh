public struct SSHExitStatus: Sendable {
  let code: Int
  let signal: String?
  let coreDumped: Bool

  static func from(
    code: Int32, signal: UnsafeMutablePointer<CChar>?, coreDumped: Int32
  ) -> SSHExitStatus {
    return SSHExitStatus(
      code: Int(code),
      signal: signal.map({ s in String(cString: s) }),
      coreDumped: coreDumped != 0)
  }
}
