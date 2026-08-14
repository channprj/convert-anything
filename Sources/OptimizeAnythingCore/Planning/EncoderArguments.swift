public enum EncoderArguments {
  public static func make(plan: ConversionPlan, media: InputMediaInfo) -> [String] {
    var arguments = [
      "-nostdin",
      "-hide_banner",
      "-loglevel",
      "error",
      "-n",
      "-i",
      plan.input.path,
    ]

    switch plan.rule.target {
    case .m4a:
      arguments += audioArguments(quality: plan.rule.quality)
    case .webm:
      arguments += videoArguments(quality: plan.rule.quality)
    case .avif:
      arguments += imageArguments(quality: plan.rule.quality, hasAlpha: media.hasAlpha)
    }

    arguments += ["-progress", "pipe:1", plan.output.temporary.path]
    return arguments
  }

  private static func audioArguments(quality: QualityPreset) -> [String] {
    ["-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", audioBitrate(for: quality)]
  }

  private static func videoArguments(quality: QualityPreset) -> [String] {
    [
      "-map",
      "0:v:0",
      "-map",
      "0:a:0?",
      "-c:v",
      "libvpx-vp9",
      "-b:v",
      "0",
      "-crf",
      videoCRF(for: quality),
      "-row-mt",
      "1",
      "-c:a",
      "libopus",
      "-b:a",
      videoAudioBitrate(for: quality),
    ]
  }

  private static func imageArguments(quality: QualityPreset, hasAlpha: Bool) -> [String] {
    var arguments: [String]
    if hasAlpha {
      arguments = [
        "-filter_complex",
        "[0:v:0]split=2[color][alpha];[alpha]alphaextract[alphaout]",
        "-map",
        "[color]",
        "-map",
        "[alphaout]",
      ]
    } else {
      arguments = ["-map", "0:v:0"]
    }

    arguments += [
      "-frames:v",
      "1",
      "-c:v",
      "libaom-av1",
      "-crf",
      imageCRF(for: quality),
      "-still-picture",
      "1",
    ]
    if hasAlpha {
      arguments += ["-metadata:s:v:1", "alpha_mode=1"]
    }
    return arguments
  }

  private static func audioBitrate(for quality: QualityPreset) -> String {
    switch quality {
    case .smaller: "96k"
    case .balanced: "160k"
    case .higherQuality: "256k"
    }
  }

  private static func videoCRF(for quality: QualityPreset) -> String {
    switch quality {
    case .smaller: "38"
    case .balanced: "32"
    case .higherQuality: "26"
    }
  }

  private static func videoAudioBitrate(for quality: QualityPreset) -> String {
    switch quality {
    case .smaller: "64k"
    case .balanced: "96k"
    case .higherQuality: "128k"
    }
  }

  private static func imageCRF(for quality: QualityPreset) -> String {
    switch quality {
    case .smaller: "38"
    case .balanced: "30"
    case .higherQuality: "22"
    }
  }
}
