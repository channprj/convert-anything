import ConvertAnythingTestSupport

@main
struct IntegrationTestMain {
  static func main() async {
    guard let environment = IntegrationEnvironment.load() else {
      print(
        "SKIP real-media integration (set CONVERT_ANYTHING_TOOL_DIR and CONVERT_ANYTHING_FIXTURE_DIR)"
      )
      return
    }

    await runTests(mediaConversionIntegrationTests(environment))
  }
}
