import Darwin
import Foundation

public struct TestCase: Sendable {
  public let name: String
  public let body: @Sendable () async throws -> Void

  public init(_ name: String, body: @escaping @Sendable () async throws -> Void) {
    self.name = name
    self.body = body
  }
}

public struct TestFailure: Error, CustomStringConvertible {
  public let description: String

  public init(description: String) {
    self.description = description
  }
}

public func expectTrue(
  _ value: @autoclosure () throws -> Bool,
  _ message: @autoclosure () -> String = "Expected condition to be true"
) throws {
  guard try value() else {
    throw TestFailure(description: message())
  }
}

public func expectEqual<T: Equatable>(
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

public func expectThrows<E: Error & Equatable>(
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

public func eventually(
  timeout: Duration = .seconds(2),
  operation: @escaping @Sendable () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await operation() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw TestFailure(description: "Condition was not met before timeout")
}

public func firstValue<Element: Sendable>(
  from stream: AsyncStream<Element>,
  timeout: Duration = .seconds(2)
) async throws -> Element {
  try await withThrowingTaskGroup(of: Element.self) { group in
    group.addTask {
      for await value in stream { return value }
      throw TestFailure(description: "Stream ended before yielding a value")
    }
    group.addTask {
      try await Task.sleep(for: timeout)
      throw TestFailure(description: "Stream did not yield before timeout")
    }
    guard let value = try await group.next() else {
      throw TestFailure(description: "No stream result task completed")
    }
    group.cancelAll()
    return value
  }
}

/// Runs every case, prints PASS/FAIL per case plus a summary line, and
/// exits nonzero when anything failed.
public func runTests(_ tests: [TestCase]) async {
  var failures: [(String, Error)] = []

  for test in tests {
    do {
      try await test.body()
      print("PASS \(test.name)")
    } catch {
      failures.append((test.name, error))
      print("FAIL \(test.name): \(error)")
    }
  }

  print("\(tests.count - failures.count) passed, \(failures.count) failed, \(tests.count) total")
  if !failures.isEmpty {
    exit(EXIT_FAILURE)
  }
}
