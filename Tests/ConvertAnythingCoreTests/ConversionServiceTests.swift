import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

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
  TestCase("success preserves restrictive source permissions on the output") {
    let source = try fixtureFile(named: "private.wav", bytes: Data([1, 2, 3]))
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: source.path
    )
    let plan = try makePlan(for: source, target: .m4a)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data([4, 5]),
      to: plan.output.temporary,
      postProbe: .aacM4A
    )

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(
      outcome,
      .succeeded(output: plan.output.final, outputByteCount: 2)
    )
    let attributes = try FileManager.default.attributesOfItem(atPath: plan.output.final.path)
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    try expectEqual(permissions, 0o600)
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
  TestCase("m4a converts to validated mp3 output") {
    let source = try fixtureFile(named: "speech.m4a")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .mp3)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data([4, 5]),
      to: plan.output.temporary,
      postProbe: .mp3Output,
      initialProbe: .aacM4A
    )

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome, .succeeded(output: plan.output.final, outputByteCount: 2))
    try expectEqual(plan.output.final.pathExtension, "mp3")
  },
  TestCase("webm converts to validated h264 mp4 output") {
    let source = try fixtureFile(named: "clip.webm")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .mp4)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data([4, 5]),
      to: plan.output.temporary,
      postProbe: .h264MP4,
      initialProbe: .vp9OpusWebM
    )

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome, .succeeded(output: plan.output.final, outputByteCount: 2))
    try expectEqual(plan.output.final.pathExtension, "mp4")
  },
  TestCase("alpha webp re-resolves the planned jpg output to png") {
    let source = try fixtureFile(named: "overlay.webp")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .jpegOrPng)
    try expectEqual(plan.output.final.pathExtension, "jpg")
    let pngOutput = try OutputPathResolver().resolve(
      input: source, fileExtension: "png", jobID: plan.id)
    let executor = FakeCommandExecutor { request in
      switch request.executable.lastPathComponent {
      case "ffmpeg":
        guard let destination = request.arguments.last else {
          throw TestFailure(description: "Missing encode destination")
        }
        try Data([4, 5]).write(to: URL(fileURLWithPath: destination))
        return CommandResult(terminationStatus: 0, standardOutput: Data(), standardError: Data())
      case "ffprobe" where request.arguments.last == pngOutput.temporary.path:
        return commandResult(for: .alphaPNGOutput)
      case "ffprobe":
        return commandResult(for: .alphaWebP)
      default:
        throw TestFailure(description: "Unexpected executable")
      }
    }

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome, .succeeded(output: pngOutput.final, outputByteCount: 2))
    try expectEqual(pngOutput.final.pathExtension, "png")
    try expectTrue(!FileManager.default.fileExists(atPath: plan.output.final.path))
    try expectTrue(!FileManager.default.fileExists(atPath: pngOutput.temporary.path))
  },
  TestCase("opaque webp keeps the planned jpg output") {
    let source = try fixtureFile(named: "sticker.webp")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let plan = try makePlan(for: source, target: .jpegOrPng)
    let executor = FakeCommandExecutor.successfullyWriting(
      Data([4, 5]),
      to: plan.output.temporary,
      postProbe: .jpegOutput,
      initialProbe: .opaqueWebP
    )

    let outcome = await makeService(executor: executor).convert(plan) { _ in }

    try expectEqual(outcome, .succeeded(output: plan.output.final, outputByteCount: 2))
    try expectEqual(plan.output.final.pathExtension, "jpg")
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
    let requestCount = await executor.requests.count
    try expectEqual(requestCount, 0)
  },
]

private func makeService(executor: any CommandExecuting) -> ConversionService {
  ConversionService(
    probe: FFprobeClient(executable: URL(fileURLWithPath: "/tools/ffprobe"), executor: executor),
    runner: FFmpegRunner(executable: URL(fileURLWithPath: "/tools/ffmpeg"), executor: executor),
    fileManager: FileManager.default
  )
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
