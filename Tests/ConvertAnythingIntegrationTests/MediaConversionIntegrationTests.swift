import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

func mediaConversionIntegrationTests(_ environment: IntegrationEnvironment)
  -> [TestCase]
{
  [
    TestCase("real audio conversion preserves source and collision bytes") {
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
      try expectTrue(media.containerNames.contains("mov"), "M4A must use a MOV-family container")
      try expectEqual(media.audioCodec, "aac", "M4A codec")
      try expectEqual(try sha256(input), originalHash, "WAV source hash")
      try expectEqual(try Data(contentsOf: collision), collisionBytes, "collision bytes")
      try expectEqual(output.lastPathComponent, "voice-converted.m4a", "collision output name")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "audio temporary files"
      )
    },
    TestCase("real movie conversion produces VP9 and Opus") {
      let input = try environment.workingCopy(of: "movie.mov")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .webm)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectTrue(media.containerNames.contains("webm"), "Movie output must be WebM")
      try expectEqual(media.videoCodec, "vp9", "WebM video codec")
      try expectEqual(media.audioCodec, "opus", "WebM audio codec")
      try expectEqual(media.width, 320, "WebM width")
      try expectEqual(media.height, 180, "WebM height")
      try expectEqual(try sha256(input), originalHash, "MOV source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "video temporary files"
      )
    },
    TestCase("real opaque image conversion produces AVIF") {
      let input = try environment.workingCopy(of: "opaque.png")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .avif)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectTrue(media.containerNames.contains("avif"), "Image output must be AVIF")
      try expectEqual(media.videoCodec, "av1", "AVIF codec")
      try expectEqual(media.width, 96, "AVIF width")
      try expectEqual(media.height, 64, "AVIF height")
      try expectTrue(!media.hasAlpha, "Opaque input must remain opaque")
      try expectEqual(try sha256(input), originalHash, "opaque PNG source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "image temporary files"
      )
    },
    TestCase("real alpha image conversion preserves alpha") {
      let input = try environment.workingCopy(of: "alpha.png")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .avif)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectEqual(media.videoCodec, "av1", "alpha AVIF codec")
      try expectEqual(media.width, 96, "alpha AVIF width")
      try expectEqual(media.height, 64, "alpha AVIF height")
      try expectTrue(media.hasAlpha, "Alpha AVIF must expose an auxiliary alpha stream")
      try expectEqual(try sha256(input), originalHash, "alpha PNG source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "alpha temporary files"
      )
    },
    TestCase("real m4a conversion produces MP3") {
      let input = try environment.workingCopy(of: "speech.m4a")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .mp3)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectEqual(output.pathExtension, "mp3", "MP3 extension")
      try expectTrue(media.containerNames.contains("mp3"), "Audio output must be MP3")
      try expectEqual(media.audioCodec, "mp3", "MP3 codec")
      try expectEqual(try sha256(input), originalHash, "M4A source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "mp3 temporary files"
      )
    },
    TestCase("real webm conversion produces H.264 MP4") {
      let input = try environment.workingCopy(of: "clip.webm")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .mp4)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectEqual(output.pathExtension, "mp4", "MP4 extension")
      try expectTrue(media.containerNames.contains("mp4"), "Video output must be MP4")
      try expectEqual(media.videoCodec, "h264", "MP4 video codec")
      try expectEqual(media.width, 320, "MP4 width")
      try expectEqual(media.height, 180, "MP4 height")
      try expectEqual(try sha256(input), originalHash, "WebM source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "mp4 temporary files"
      )
    },
    TestCase("real opaque webp conversion produces JPEG") {
      let input = try environment.workingCopy(of: "opaque.webp")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .jpegOrPng)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectEqual(output.pathExtension, "jpg", "JPEG extension")
      try expectEqual(media.videoCodec, "mjpeg", "JPEG codec")
      try expectEqual(media.width, 96, "JPEG width")
      try expectEqual(media.height, 64, "JPEG height")
      try expectTrue(!media.hasAlpha, "Opaque WebP must produce an opaque JPEG")
      try expectEqual(try sha256(input), originalHash, "opaque WebP source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "jpeg temporary files"
      )
    },
    TestCase("real alpha webp conversion produces PNG with alpha") {
      let input = try environment.workingCopy(of: "alpha.webp")
      let originalHash = try sha256(input)
      let plan = try integrationPlan(for: input, target: .jpegOrPng)

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectEqual(output.pathExtension, "png", "PNG extension")
      try expectEqual(media.videoCodec, "png", "PNG codec")
      try expectEqual(media.width, 96, "PNG width")
      try expectEqual(media.height, 64, "PNG height")
      try expectTrue(media.hasAlpha, "Alpha WebP must keep alpha in PNG")
      try expectEqual(try sha256(input), originalHash, "alpha WebP source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [], "png temporary files"
      )
    },
    TestCase("real HEIC default conversion produces JPEG") {
      let input = try environment.workingCopy(of: "opaque.heic")
      let originalHash = try sha256(input)
      let rule = try defaultRule(for: "heic")
      let plan = try await ConversionPlanner().plan(input: input, rule: rule, jobID: UUID())

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectEqual(output.pathExtension, "jpg", "HEIC JPEG extension")
      try expectEqual(media.videoCodec, "mjpeg", "HEIC JPEG codec")
      try expectEqual(media.width, 96, "HEIC JPEG width")
      try expectEqual(media.height, 64, "HEIC JPEG height")
      try expectTrue(!media.hasAlpha, "Opaque HEIC must produce an opaque JPEG")
      try expectEqual(try sha256(input), originalHash, "HEIC source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [],
        "HEIC temporary files"
      )
    },
    TestCase("real alpha HEIC default conversion produces PNG with alpha") {
      let input = try environment.workingCopy(of: "alpha.heic")
      let originalHash = try sha256(input)
      let rule = try defaultRule(for: "heic")
      let plan = try await ConversionPlanner().plan(input: input, rule: rule, jobID: UUID())

      let output = try successfulOutput(
        from: await environment.service().convert(plan) { _ in }
      )
      let media = try await environment.probe(output)
      try expectEqual(output.pathExtension, "png", "HEIC PNG extension")
      try expectEqual(media.videoCodec, "png", "HEIC PNG codec")
      try expectEqual(media.width, 96, "HEIC PNG width")
      try expectEqual(media.height, 64, "HEIC PNG height")
      try expectTrue(media.hasAlpha, "Alpha HEIC must keep alpha in PNG")
      let outputAlpha = try await environment.decodedAlphaPlane(from: output)
      let inputAlpha = try await environment.decodedAlphaPlane(from: input, streamIndex: 1)
      try expectEqual(outputAlpha, inputAlpha, "HEIC PNG alpha pixels")
      try expectEqual(try sha256(input), originalHash, "alpha HEIC source hash")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [],
        "alpha HEIC temporary files"
      )
    },
    TestCase("corrupt media leaves no final or temporary artifact") {
      let directory = environment.fixtureDirectory
        .appendingPathComponent("test-runs", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let input = directory.appendingPathComponent("corrupt.mov")
      try Data("not media".utf8).write(to: input)
      let plan = try integrationPlan(for: input, target: .webm)

      let outcome = await environment.service().convert(plan) { _ in }
      guard case .failed(let failure) = outcome else {
        throw TestFailure(description: "Expected corrupt media failure, got \(outcome)")
      }
      try expectEqual(failure.category, .invalidMedia, "corrupt media category")
      try expectTrue(
        !FileManager.default.fileExists(atPath: plan.output.final.path), "No final output")
      try expectEqual(try hiddenTemporaryFiles(in: directory), [], "corrupt temporary files")
    },
    TestCase("canceling a live conversion removes every artifact") {
      let input = try environment.workingCopy(of: "long.mov")
      let plan = try integrationPlan(for: input, target: .webm)
      let service = environment.service()
      let conversion = Task { await service.convert(plan) { _ in } }

      try await eventually(timeout: .seconds(8)) {
        FileManager.default.fileExists(atPath: plan.output.temporary.path)
      }
      await service.cancel(jobID: plan.id)
      let outcome = await conversion.value
      try expectEqual(outcome, .canceled, "canceled conversion outcome")
      try expectTrue(
        !FileManager.default.fileExists(atPath: plan.output.final.path), "No canceled final")
      try expectEqual(
        try hiddenTemporaryFiles(in: input.deletingLastPathComponent()), [],
        "canceled temporary files")
    },
  ]
}
