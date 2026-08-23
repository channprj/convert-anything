import ConvertAnythingTestSupport

@main
struct MacTestMain {
  static func main() async {
    await runTests(
      dropPresentationCoordinatorTests + statusBarDropViewTests + appViewModelTests
        + localNotificationServiceTests + popoverViewTests + brandGlyphTests
    )
  }
}
