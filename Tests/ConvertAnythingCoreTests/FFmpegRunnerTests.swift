import ConvertAnythingCore
import Foundation

let ffmpegRunnerTests: [TestCase] = [
  TestCase("foundation executor launches directly and drains standard output") {
    let executor = FoundationCommandExecutor()
    let recorder = LineRecorder()
    let request = CommandRequest(
      id: UUID(),
      executable: URL(fileURLWithPath: "/usr/bin/printf"),
      arguments: ["first\\nsecond\\n"]
    )

    let result = try await executor.execute(request) { line in recorder.append(line) }

    try expectEqual(result.terminationStatus, 0)
    try expectEqual(String(decoding: result.standardOutput, as: UTF8.self), "first\nsecond\n")
    try expectEqual(result.standardError, Data())
    try expectEqual(recorder.values, ["first", "second"])
  },
  TestCase("progress parser emits only bounded progress records") {
    var parser = FFmpegProgressParser(durationSeconds: 2)
    try expectEqual(parser.consume("out_time_us=1000000"), nil)
    try expectEqual(parser.consume("progress=continue"), 0.5)
    try expectEqual(parser.consume("out_time_us=9000000"), nil)
    try expectEqual(parser.consume("progress=end"), 1.0)
  },
  TestCase("progress parser handles missing duration without division") {
    var parser = FFmpegProgressParser(durationSeconds: nil)
    try expectEqual(parser.consume("out_time_us=1000000"), nil)
    try expectEqual(parser.consume("progress=continue"), nil)
    try expectEqual(parser.consume("progress=end"), 1.0)
  },
  TestCase("runner sends planned arguments and forwards parsed progress") {
    let plan = try makePlan(source: "movie.mov", target: .webm, quality: .balanced)
    defer { try? FileManager.default.removeItem(at: plan.input.deletingLastPathComponent()) }
    let progressText = "out_time_us=1000000\nprogress=continue\nout_time_us=2000000\nprogress=end\n"
    let executor = FakeCommandExecutor { _ in
      CommandResult(
        terminationStatus: 0,
        standardOutput: Data(progressText.utf8),
        standardError: Data()
      )
    }
    let runner = FFmpegRunner(
      executable: URL(fileURLWithPath: "/tools/ffmpeg"),
      executor: executor
    )
    let recorder = ProgressRecorder()

    let result = try await runner.run(
      plan: plan,
      media: InputMediaInfo(
        containerNames: ["mov"],
        durationSeconds: 2,
        videoCodec: "h264",
        audioCodec: "aac",
        width: 320,
        height: 180,
        channelCount: 2,
        hasAlpha: false,
        rotationDegrees: nil
      ),
      progress: { value in recorder.append(value) }
    )

    try expectEqual(result.terminationStatus, 0)
    try expectEqual(recorder.values, [0.5, 1.0])
    let requests = await executor.requests
    try expectEqual(requests.count, 1)
    try expectEqual(requests[0].id, plan.id)
    try expectEqual(requests[0].executable.path, "/tools/ffmpeg")
    try expectEqual(
      requests[0].arguments, EncoderArguments.make(plan: plan, media: .videoWithAudioFixture))
  },
  TestCase("runner cancel terminates the command with the job ID") {
    let executor = FakeCommandExecutor.probeJSON("{}")
    let runner = FFmpegRunner(
      executable: URL(fileURLWithPath: "/tools/ffmpeg"),
      executor: executor
    )
    let jobID = UUID(uuidString: "40000000-0000-0000-0000-000000000000")!

    await runner.cancel(jobID: jobID)

    let terminatedIDs = await executor.terminatedIDs
    try expectEqual(terminatedIDs, [jobID])
  },
]

private final class ProgressRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Double] = []

  var values: [Double] {
    lock.withLock { storage }
  }

  func append(_ value: Double) {
    lock.withLock { storage.append(value) }
  }
}

private final class LineRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  var values: [String] {
    lock.withLock { storage }
  }

  func append(_ value: String) {
    lock.withLock { storage.append(value) }
  }
}
