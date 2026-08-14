import Foundation

func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("optimize-anything-tests", isDirectory: true)
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

struct TestCase: Sendable {
  let name: String
  let body: @Sendable () async throws -> Void

  init(_ name: String, body: @escaping @Sendable () async throws -> Void) {
    self.name = name
    self.body = body
  }
}

struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

func expectTrue(
  _ value: @autoclosure () throws -> Bool,
  _ message: @autoclosure () -> String = "Expected condition to be true"
) throws {
  guard try value() else {
    throw TestFailure(description: message())
  }
}

func expectEqual<T: Equatable>(
  _ actual: @autoclosure () throws -> T,
  _ expected: @autoclosure () throws -> T,
  _ context: String = ""
) throws {
  let actualValue = try actual()
  let expectedValue = try expected()
  guard actualValue == expectedValue else {
    let prefix = context.isEmpty ? "" : "\(context): "
    throw TestFailure(
      description:
        "\(prefix)expected \(String(describing: expectedValue)), got \(String(describing: actualValue))"
    )
  }
}

func expectThrows<E: Error & Equatable>(
  _ expected: E,
  operation: @Sendable () async throws -> Void
) async throws {
  do {
    try await operation()
  } catch let error as E {
    try expectEqual(error, expected)
    return
  } catch {
    throw TestFailure(description: "Expected \(expected), got \(error)")
  }

  throw TestFailure(description: "Expected \(expected), but operation succeeded")
}
