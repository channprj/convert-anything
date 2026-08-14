import Darwin

@main
struct MacTestMain {
  static func main() async {
    let tests = statusBarDropViewTests + appViewModelTests + localNotificationServiceTests
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
