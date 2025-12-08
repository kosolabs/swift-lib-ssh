import XCTest

func XCTAsyncAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line,
  _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    // expected error to be thrown, but it was not
    let customMessage = message()
    if customMessage.isEmpty {
      XCTFail("Asynchronous call did not throw an error.", file: file, line: line)
    } else {
      XCTFail(customMessage, file: file, line: line)
    }
  } catch {
    errorHandler(error)
  }
}

func XCTAsyncAssertTrue(
  _ expression: @autoclosure () async throws -> Bool,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    let result = try await expression()
    if result == false {
      let customMessage = message()
      if customMessage.isEmpty {
        XCTFail("Asynchronous XCTAssertTrue failed.", file: file, line: line)
      } else {
        XCTFail(customMessage, file: file, line: line)
      }
    }
  } catch {
    let customMessage = message()
    if customMessage.isEmpty {
      XCTFail("Asynchronous XCTAssertTrue threw error: \(error).", file: file, line: line)
    } else {
      XCTFail(customMessage, file: file, line: line)
    }
  }
}

func XCTAsyncAssertFalse(
  _ expression: @autoclosure () async throws -> Bool,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    let result = try await expression()
    if result == true {
      let customMessage = message()
      if customMessage.isEmpty {
        XCTFail("Asynchronous XCTAssertFalse failed.", file: file, line: line)
      } else {
        XCTFail(customMessage, file: file, line: line)
      }
    }
  } catch {
    let customMessage = message()
    if customMessage.isEmpty {
      XCTFail("Asynchronous XCTAssertFalse threw error: \(error).", file: file, line: line)
    } else {
      XCTFail(customMessage, file: file, line: line)
    }
  }
}
