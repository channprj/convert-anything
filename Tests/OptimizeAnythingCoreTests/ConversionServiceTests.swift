import Foundation
import OptimizeAnythingCore

let conversionServiceTests: [TestCase] = [
  TestCase("success atomically finalizes and leaves source untouched") {
    let sourceBytes = Data([1, 2, 3])
    let source = try fixtureFile(named: "voice.wav", bytes: sourceBytes)
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .m4a)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data([4, 5]),
      to: plan.output.temporary,
      postProbe: .aacM4A
    )
    let service = makeService(executor: executor)

    let outcome = await service.convert(plan) { _ in }

    try expectEqual(
      outcome,
      .succeeded(output: plan.output.final, outputByteCount: 2)
    )
    try expectEqual(try Data(contentsOf: source), sourceBytes)
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.temporary.path))
    try expectEqual(try Data(contentsOf: plan.output.final), Data([4, 5]))
    let requests = await executor.requests
    try expectEqual(
      requests.map { $0.executable.lastPathComponent }, ["ffprobe", "ffmpeg", "ffprobe"])
  },
  TestCase("nonzero encoder exit removes temporary and does not finalize") {
    let source = try fixtureFile(named: "bad.mov", bytes: Data([1]))
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .webm)
    let service = makeService(
      executor: FakeCommandExecutor.failure(status: 1, stderr: "header\nInvalid data found")
    )

    let outcome = await service.convert(plan) { _ in }

    try expectEqual(outcome.failureCategory, .invalidMedia)
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.temporary.path))
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.final.path))
  },
  TestCase("zero-byte encoder output is rejected and cleaned") {
    let source = try fixtureFile(named: "voice.wav")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .m4a)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data(),
      to: plan.output.temporary,
      postProbe: .aacM4A
    )

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome.failureCategory, .invalidOutput)
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.temporary.path))
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.final.path))
  },
  TestCase("mismatched post-probe codec is rejected") {
    let source = try fixtureFile(named: "movie.mov")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .webm)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data([8]),
      to: plan.output.temporary,
      postProbe: .aacM4A
    )

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome.failureCategory, .invalidOutput)
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.temporary.path))
  },
  TestCase("alpha input requires an alpha AVIF postcondition") {
    let source = try fixtureFile(named: "overlay.png")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .avif)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data([8]),
      to: plan.output.temporary,
      postProbe: .opaqueAVIF,
      initialProbe: .alphaImageFixture
    )

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome.failureCategory, .invalidOutput)
  },
  TestCase("cancel during encoding terminates by job ID and returns canceled") {
    let source = try fixtureFile(named: "movie.mov")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .webm)
    let gate = CommandGate()
    let executor = FakeCommandExecutor { request in
      if request.executable.lastPathComponent == "ffprobe" {
        return commandResult(for: .videoWithAudioFixture)
      }
      return await gate.suspend()
    }
    let service = makeService(executor: executor)
    let conversion = Task { await service.convert(plan) { _ in } }
    await gate.waitUntilEntered()

    await service.cancel(jobID: plan.id)
    await gate.finish(status: 15)
    let outcome = await conversion.value

    try expectEqual(outcome, .canceled)
    let terminatedIDs = await executor.terminatedIDs
    try expectEqual(terminatedIDs, [plan.id])
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.temporary.path))
  },
  TestCase("final-name race preserves competing file and reports finalization failure") {
    let source = try fixtureFile(named: "voice.wav")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .m4a)
    let competingBytes = Data([7, 7, 7])
    let executor = FakeCommandExecutor { request in
      switch request.executable.lastPathComponent {
      case "ffmpeg":
        try Data([4, 5]).write(to: plan.output.temporary)
        return CommandResult(terminationStatus: 0, standardOutput: Data(), standardError: Data())
      case "ffprobe" where request.arguments.last == plan.output.temporary.path:
        try competingBytes.write(to: plan.output.final)
        return commandResult(for: .aacM4A)
      case "ffprobe":
        return commandResult(for: .audioFixture)
      default:
        throw TestFailure(description: "Unexpected executable")
      }
    }

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome.failureCategory, .finalizationFailed)
    try expectEqual(try Data(contentsOf: plan.output.final), competingBytes)
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.temporary.path))
  },
  TestCase("missing input is classified without launching a tool") {
    let source = try fixtureFile(named: "voice.wav")
    let directory = source.deletingLastPathComponent()
    let plan = try makePlan(for: source, target: .m4a)
    try FileManager.default.removeItem(at: source)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executor = FakeCommandExecutor.probeJSON("{}")

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome.failureCategory, .inputUnavailable)
    let requestCount = await executor.requestCount()
    try expectEqual(requestCount, 0)
  },
]

actor FakeCommandExecutor: CommandExecuting {
  typealias Script = @Sendable (CommandRequest) async throws -> CommandResult

  private let script: Script
  private(set) var requests: [CommandRequest] = []
  private(set) var terminatedIDs: [UUID] = []

  init(script: @escaping Script) {
    self.script = script
  }

  func execute(
    _ request: CommandRequest,
    onStandardOutputLine: @escaping @Sendable (String) -> Void
  ) async throws -> CommandResult {
    requests.append(request)
    let result = try await script(request)
    if let output = String(data: result.standardOutput, encoding: .utf8) {
      for line in output.split(whereSeparator: \.isNewline) {
        onStandardOutputLine(String(line))
      }
    }
    return result
  }

  func terminate(commandID: UUID) async {
    terminatedIDs.append(commandID)
  }

  static func probeJSON(_ json: String) -> FakeCommandExecutor {
    FakeCommandExecutor { _ in
      return CommandResult(
        terminationStatus: 0,
        standardOutput: Data(json.utf8),
        standardError: Data()
      )
    }
  }

  static func failure(status: Int32, stderr: String) -> FakeCommandExecutor {
    FakeCommandExecutor { request in
      if request.executable.lastPathComponent == "ffprobe" {
        return commandResult(for: initialMediaInfo(for: request.arguments.last ?? ""))
      }
      if let path = request.arguments.last {
        try Data([9]).write(to: URL(fileURLWithPath: path))
      }
      return CommandResult(
        terminationStatus: status,
        standardOutput: Data(),
        standardError: Data(stderr.utf8)
      )
    }
  }

  static func successfullyWriting(
    _ data: Data,
    to temporary: URL,
    postProbe: InputMediaInfo,
    initialProbe: InputMediaInfo? = nil
  ) -> FakeCommandExecutor {
    FakeCommandExecutor { request in
      switch request.executable.lastPathComponent {
      case "ffmpeg":
        try data.write(to: temporary)
        return CommandResult(terminationStatus: 0, standardOutput: Data(), standardError: Data())
      case "ffprobe" where request.arguments.last == temporary.path:
        return commandResult(for: postProbe)
      case "ffprobe":
        return commandResult(
          for: initialProbe ?? initialMediaInfo(for: request.arguments.last ?? "")
        )
      default:
        throw TestFailure(description: "Unexpected executable")
      }
    }
  }

  func requestCount() -> Int {
    requests.count
  }
}

private func makeService(executor: any CommandExecuting) -> ConversionService {
  ConversionService(
    probe: FFprobeClient(executable: URL(fileURLWithPath: "/tools/ffprobe"), executor: executor),
    runner: FFmpegRunner(executable: URL(fileURLWithPath: "/tools/ffmpeg"), executor: executor),
    fileManager: FileManager.default
  )
}

private func initialMediaInfo(for path: String) -> InputMediaInfo {
  switch URL(fileURLWithPath: path).pathExtension.lowercased() {
  case "wav", "aiff", "flac", "caf":
    .audioFixture
  case "mov", "mp4", "mkv":
    .videoWithAudioFixture
  case "png":
    .alphaImageFixture
  default:
    .opaqueImageFixture
  }
}

private func commandResult(for info: InputMediaInfo) -> CommandResult {
  CommandResult(
    terminationStatus: 0,
    standardOutput: probeJSON(for: info),
    standardError: Data()
  )
}

private func probeJSON(for info: InputMediaInfo) -> Data {
  let format = FakeProbeFormat(
    formatName: info.containerNames.joined(separator: ","),
    duration: info.durationSeconds.map { String($0) }
  )
  var streams: [FakeProbeStream] = []
  if let videoCodec = info.videoCodec {
    streams.append(
      FakeProbeStream(
        codecType: "video",
        codecName: videoCodec,
        pixelFormat: info.hasAlpha ? "rgba" : "yuv420p",
        width: info.width,
        height: info.height,
        channels: nil,
        sideData: info.rotationDegrees.map { [FakeProbeSideData(rotation: $0)] }
      )
    )
    if info.hasAlpha && info.containerNames.contains("avif") {
      streams.append(
        FakeProbeStream(
          codecType: "video",
          codecName: videoCodec,
          pixelFormat: "gray",
          width: info.width,
          height: info.height,
          channels: nil,
          sideData: nil
        )
      )
    }
  }
  if let audioCodec = info.audioCodec {
    streams.append(
      FakeProbeStream(
        codecType: "audio",
        codecName: audioCodec,
        pixelFormat: nil,
        width: nil,
        height: nil,
        channels: info.channelCount,
        sideData: nil
      )
    )
  }
  return (try? JSONEncoder().encode(FakeProbeResponse(format: format, streams: streams))) ?? Data()
}

private struct FakeProbeResponse: Encodable {
  let format: FakeProbeFormat
  let streams: [FakeProbeStream]
}

private struct FakeProbeFormat: Encodable {
  let formatName: String
  let duration: String?

  private enum CodingKeys: String, CodingKey {
    case formatName = "format_name"
    case duration
  }
}

private struct FakeProbeStream: Encodable {
  let codecType: String
  let codecName: String
  let pixelFormat: String?
  let width: Int?
  let height: Int?
  let channels: Int?
  let sideData: [FakeProbeSideData]?

  private enum CodingKeys: String, CodingKey {
    case codecType = "codec_type"
    case codecName = "codec_name"
    case pixelFormat = "pix_fmt"
    case width
    case height
    case channels
    case sideData = "side_data_list"
  }
}

private struct FakeProbeSideData: Encodable {
  let rotation: Int
}

private actor CommandGate {
  private var entered = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var resultWaiter: CheckedContinuation<CommandResult, Never>?

  func suspend() async -> CommandResult {
    entered = true
    for waiter in entryWaiters {
      waiter.resume()
    }
    entryWaiters.removeAll()
    return await withCheckedContinuation { resultWaiter = $0 }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { entryWaiters.append($0) }
  }

  func finish(status: Int32) {
    resultWaiter?.resume(
      returning: CommandResult(
        terminationStatus: status,
        standardOutput: Data(),
        standardError: Data("Canceled".utf8)
      )
    )
    resultWaiter = nil
  }
}
