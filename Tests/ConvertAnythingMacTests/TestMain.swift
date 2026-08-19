import ConvertAnythingTestSupport

@main
struct MacTestMain {
  static func main() async {
    await runTests(statusBarDropViewTests + appViewModelTests + localNotificationServiceTests)
  }
}
