import Foundation
import OptimizeAnythingCore

let encoderArgumentsTests: [TestCase] = audioArgumentTests + videoArgumentTests + imageArgumentTests

private let audioProfiles: [(QualityPreset, String)] = [
  (.smaller, "96k"),
  (.balanced, "160k"),
  (.higherQuality, "256k"),
]

private let audioArgumentTests: [TestCase] = audioProfiles.map { quality, bitrate in
  TestCase("\(quality.rawValue) audio arguments are explicit and shell free") {
    let plan = try makePlan(source: "voice with $dollars.wav", target: .m4a, quality: quality)
    defer { try? FileManager.default.removeItem(at: plan.input.deletingLastPathComponent()) }

    try expectEqual(
      EncoderArguments.make(plan: plan, media: .audioFixture),
      commonInputArguments(plan)
        + ["-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", bitrate]
        + outputArguments(plan)
    )
  }
}

private let videoProfiles: [(QualityPreset, String, String)] = [
  (.smaller, "38", "64k"),
  (.balanced, "32", "96k"),
  (.higherQuality, "26", "128k"),
]

private let videoArgumentTests: [TestCase] = videoProfiles.map { quality, crf, audioBitrate in
  TestCase("\(quality.rawValue) video arguments use VP9 and optional Opus") {
    let plan = try makePlan(source: "movie.mov", target: .webm, quality: quality)
    defer { try? FileManager.default.removeItem(at: plan.input.deletingLastPathComponent()) }

    try expectEqual(
      EncoderArguments.make(plan: plan, media: .videoWithAudioFixture),
      commonInputArguments(plan)
        + [
          "-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libvpx-vp9", "-b:v", "0", "-crf",
          crf, "-row-mt", "1", "-c:a", "libopus", "-b:a", audioBitrate,
        ]
        + outputArguments(plan)
    )
  }
}

private let imageProfiles: [(QualityPreset, String)] = [
  (.smaller, "38"),
  (.balanced, "30"),
  (.higherQuality, "22"),
]

private let imageArgumentTests: [TestCase] = imageProfiles.flatMap { quality, crf in
  [
    TestCase("\(quality.rawValue) opaque image arguments encode one AVIF stream") {
      let plan = try makePlan(source: "photo.jpg", target: .avif, quality: quality)
      defer { try? FileManager.default.removeItem(at: plan.input.deletingLastPathComponent()) }

      try expectEqual(
        EncoderArguments.make(plan: plan, media: .opaqueImageFixture),
        commonInputArguments(plan)
          + [
            "-map", "0:v:0", "-frames:v", "1", "-c:v", "libaom-av1", "-crf", crf,
            "-still-picture", "1",
          ]
          + outputArguments(plan)
      )
    },
    TestCase("\(quality.rawValue) alpha image arguments encode color and auxiliary alpha") {
      let plan = try makePlan(source: "overlay.png", target: .avif, quality: quality)
      defer { try? FileManager.default.removeItem(at: plan.input.deletingLastPathComponent()) }

      try expectEqual(
        EncoderArguments.make(plan: plan, media: .alphaImageFixture),
        commonInputArguments(plan)
          + [
            "-filter_complex", "[0:v:0]split=2[color][alpha];[alpha]alphaextract[alphaout]",
            "-map", "[color]", "-map", "[alphaout]", "-frames:v", "1", "-c:v", "libaom-av1",
            "-crf", crf, "-still-picture", "1", "-metadata:s:v:1", "alpha_mode=1",
          ]
          + outputArguments(plan)
      )
    },
  ]
}

private func commonInputArguments(_ plan: ConversionPlan) -> [String] {
  ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", plan.input.path]
}

private func outputArguments(_ plan: ConversionPlan) -> [String] {
  ["-progress", "pipe:1", plan.output.temporary.path]
}
