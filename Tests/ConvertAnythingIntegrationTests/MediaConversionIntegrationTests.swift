import ConvertAnythingCore
import Foundation

func mediaConversionIntegrationTests(_ environment: IntegrationEnvironment)
  -> [IntegrationTestCase]
{
  [
    IntegrationTestCase(name: "real audio conversion preserves source and collision bytes") {
      let input = try environment.workingCopy(of: "voice.wav")
      let originalHash = try sha256(input)
      let collision = input.deletingPathExtension().appendingPathExtension("m4a")
      let collisionBytes = Data("existing-output".utf8)
      try collisionBytes.write(to: collision)
      let plan = try integrationPlan(for: input, target: .m4a)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try require(media.containerNames.contains("mov"), "M4A must use a MOV-family container")
      try requireEqual(media.audioCodec, "aac", "M4A codec")
      try requireEqual(try sha256(input), originalHash, "WAV source hash")
      try requireEqual(try Data(contentsOf: collision), collisionBytes, "collision bytes")
      try requireEqual(output.lastPathComponent, "voice-converted.m4a", "collision output name")
      try requireEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "audio temporary files"
      )
    },
    IntegrationTestCase(name: "real movie conversion produces VP9 and Opus") {
      let input = try environment.workingCopy(of: "movie.mov")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .webm)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try require(media.containerNames.contains("webm"), "Movie output must be WebM")
      try requireEqual(media.videoCodec, "vp9", "WebM video codec")
      try requireEqual(media.audioCodec, "opus", "WebM audio codec")
      try requireEqual(media.width, 320, "WebM width")
      try requireEqual(media.height, 180, "WebM height")
      try requireEqual(try sha256(input), originalHash, "MOV source hash")
      try requireEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "video temporary files"
      )
    },
    IntegrationTestCase(name: "real opaque image conversion produces AVIF") {
      let input = try environment.workingCopy(of: "opaque.png")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .avif)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try require(media.containerNames.contains("avif"), "Image output must be AVIF")
      try requireEqual(media.videoCodec, "av1", "AVIF codec")
      try requireEqual(media.width, 96, "AVIF width")
      try requireEqual(media.height, 64, "AVIF height")
      try require(!media.hasAlpha, "Opaque input must remain opaque")
      try requireEqual(try sha256(input), originalHash, "opaque PNG source hash")
      try requireEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "image temporary files"
      )
    },
    IntegrationTestCase(name: "real alpha image conversion preserves alpha") {
      let input = try environment.workingCopy(of: "alpha.png")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .avif)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try requireEqual(media.videoCodec, "av1", "alpha AVIF codec")
      try requireEqual(media.width, 96, "alpha AVIF width")
      try requireEqual(media.height, 64, "alpha AVIF height")
      try require(media.hasAlpha, "Alpha AVIF must expose an auxiliary alpha stream")
      try requireEqual(try sha256(input), originalHash, "alpha PNG source hash")
      try requireEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "alpha temporary files"
      )
    },
    IntegrationTestCase(name: "corrupt media leaves no final or temporary artifact") {
      let directory = environment.fixtureDirectory
        .appendingPathComponent("test-runs", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let input = directory.appendingPathComponent("corrupt.mov")
      try Data("not media".utf8).write(to: input)
      let plan = try integrationPlan(for: input, target: .webm)

      let outcome = await environment.service().convert(plan) { _ in }
      guard case .failed(let failure) = outcome else {
        throw IntegrationTestFailure(description: "Expected corrupt media failure, got \(outcome)")
      }
      try requireEqual(failure.category, .invalidMedia, "corrupt media category")
      try require(
        !FileManager.default.fileExists(atPath: plan.output.final.path), "No final output")
      try requireEqual(try hiddenTemporaryFiles(in: directory), [], "corrupt temporary files")
    },
    IntegrationTestCase(name: "canceling a live conversion removes every artifact") {
      let input = try environment.workingCopy(of: "long.mov")
      let plan = try integrationPlan(for: input, target: .webm)
      let service = environment.service()
      let conversion = Task { await service.convert(plan) { _ in } }

      try await waitUntil(timeout: .seconds(8)) {
        FileManager.default.fileExists(atPath: plan.output.temporary.path)
      }
      await service.cancel(jobID: plan.id)
      let outcome = await conversion.value
      try requireEqual(outcome, .canceled, "canceled conversion outcome")
      try require(
        !FileManager.default.fileExists(atPath: plan.output.final.path), "No canceled final")
      try requireEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [],
        "canceled temporary files")
    },
  ]
}
