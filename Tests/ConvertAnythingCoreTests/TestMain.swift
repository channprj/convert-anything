import ConvertAnythingTestSupport

@main
struct TestMain {
  static func main() async {
    await runTests(
      ruleCatalogTests + mappingStoreTests + dropAdmissionServiceTests + conversionPlannerTests
        + outputPathResolverTests + encoderArgumentsTests + ffprobeClientTests + ffmpegRunnerTests
        + conversionServiceTests + conversionQueueTests + drainSummaryTests
    )
  }
}
