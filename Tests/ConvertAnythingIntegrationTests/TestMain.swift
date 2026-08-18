import Darwin
import Foundation

@main
struct IntegrationTestMain {
  static func main() async {
    guard let environment = IntegrationEnvironment.load() else {
      print(
        "SKIP real-media integration (set CONVERT_ANYTHING_TOOL_DIR and CONVERT_ANYTHING_FIXTURE_DIR)"
      )
      return
    }

    let tests = mediaConversionIntegrationTests(environment)
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
    if !failures.isEmpty { exit(EXIT_FAILURE) }
  }
}
