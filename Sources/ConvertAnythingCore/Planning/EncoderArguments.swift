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
      arguments += audioArguments(codec: "aac", quality: plan.rule.quality)
    case .mp3:
      arguments += audioArguments(codec: "libmp3lame", quality: plan.rule.quality)
    case .webm:
      arguments += videoArguments(quality: plan.rule.quality)
    case .mp4:
      arguments += mp4Arguments(quality: plan.rule.quality)
    case .avif:
      arguments += imageArguments(quality: plan.rule.quality, hasAlpha: media.hasAlpha)
    case .jpegOrPng:
      if let colorGrid = media.heicColorGrid {
        arguments += heicGridArguments(
          color: colorGrid,
          alphaGrid: media.heicAlphaGrid,
          alphaStreamIndex: media.auxiliaryAlphaVideoStreamIndex,
          orientation: media.heicOrientation,
          quality: plan.rule.quality
        )
      } else if media.containerNames.contains("heic"),
        let alphaStreamIndex = media.auxiliaryAlphaVideoStreamIndex
      {
        arguments += heicPNGArguments(alphaStreamIndex: alphaStreamIndex)
      } else {
        arguments += media.hasAlpha ? pngArguments() : jpegArguments(quality: plan.rule.quality)
      }
    }

    arguments += ["-progress", "pipe:1", plan.output.temporary.path]
    return arguments
  }

  private static func audioArguments(codec: String, quality: QualityPreset) -> [String] {
    ["-map", "0:a:0", "-vn", "-c:a", codec, "-b:a", audioBitrate(for: quality)]
  }

  private static func mp4Arguments(quality: QualityPreset) -> [String] {
    [
      "-map",
      "0:v:0",
      "-map",
      "0:a:0?",
      "-c:v",
      "h264_videotoolbox",
      "-q:v",
      mp4Quality(for: quality),
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "aac",
      "-b:a",
      videoAudioBitrate(for: quality),
      "-movflags",
      "+faststart",
    ]
  }

  private static func jpegArguments(quality: QualityPreset) -> [String] {
    ["-map", "0:v:0", "-frames:v", "1", "-c:v", "mjpeg", "-q:v", jpegQuality(for: quality)]
  }

  private static func pngArguments() -> [String] {
    ["-map", "0:v:0", "-frames:v", "1", "-c:v", "png"]
  }

  private static func heicPNGArguments(alphaStreamIndex: Int) -> [String] {
    [
      "-filter_complex", "[0:v:0][0:v:\(alphaStreamIndex)]alphamerge[out]", "-map", "[out]",
      "-frames:v", "1", "-c:v", "png",
    ]
  }

  /// Rebuild the clean HEIC frame. Mapping the first tile alone stores only
  /// that tile, which is the cropped image FFmpeg 8.0 produces for a grid.
  private static func heicGridArguments(
    color: HEICImageGrid,
    alphaGrid: HEICImageGrid?,
    alphaStreamIndex: Int?,
    orientation: Int,
    quality: QualityPreset
  ) -> [String] {
    let orientationFilter = heicOrientationFilter(orientation)
    var filters: [String] = []
    let hasAlpha = alphaGrid != nil || alphaStreamIndex != nil
    if let alphaGrid {
      filters.append(gridAssembly(color, label: "color"))
      filters.append(gridAssembly(alphaGrid, label: "alpha"))
      filters.append(mergeAlpha(orientationFilter))
    } else if let alphaStreamIndex {
      filters.append(gridAssembly(color, label: "color"))
      filters.append(mergeAlpha(orientationFilter, alphaStreamIndex: alphaStreamIndex))
    } else {
      filters.append(gridAssembly(color, label: "out", orientationFilter: orientationFilter))
    }

    var arguments = [
      "-filter_complex", filters.joined(separator: ";"), "-map", "[out]", "-frames:v", "1",
    ]
    if hasAlpha {
      arguments += ["-c:v", "png"]
    } else {
      arguments += ["-c:v", "mjpeg", "-q:v", jpegQuality(for: quality)]
    }
    return arguments
  }

  private static func mergeAlpha(_ orientationFilter: String?, alphaStreamIndex: Int? = nil)
    -> String
  {
    let alphaInput = alphaStreamIndex.map { "[0:v:\($0)]" } ?? "[alpha]"
    let transform = orientationFilter.map { ",\($0)" } ?? ""
    return "[color]\(alphaInput)alphamerge\(transform)[out]"
  }

  private static func gridAssembly(
    _ grid: HEICImageGrid,
    label: String,
    orientationFilter: String? = nil
  ) -> String {
    let inputs = grid.tiles.map { "[0:\($0.streamIndex)]" }.joined()
    var chain: String
    if grid.tiles.count == 1 {
      chain =
        grid.needsCrop
        ? "crop=\(grid.width):\(grid.height):\(grid.originX):\(grid.originY)"
        : "copy"
    } else {
      let layout = grid.tiles.map { "\($0.x)_\($0.y)" }.joined(separator: "|")
      chain = "xstack=inputs=\(grid.tiles.count):layout=\(layout)"
      if grid.needsCrop {
        chain += ",crop=\(grid.width):\(grid.height):\(grid.originX):\(grid.originY)"
      }
    }
    if let orientationFilter {
      chain += ",\(orientationFilter)"
    }
    return "\(inputs)\(chain)[\(label)]"
  }

  /// Display transforms checked against ImageIO for EXIF orientations 1...8.
  private static func heicOrientationFilter(_ orientation: Int) -> String? {
    switch orientation {
    case 2: "hflip"
    case 3: "hflip,vflip"
    case 4: "vflip"
    case 5: "transpose=0"
    case 6: "transpose=1"
    case 7: "transpose=3"
    case 8: "transpose=2"
    default: nil
    }
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
        "[0:v:0]split=2[color][alpha];[alpha]alphaextract,setparams=colorspace=bt709[alphaout]",
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

  private static func mp4Quality(for quality: QualityPreset) -> String {
    switch quality {
    case .smaller: "40"
    case .balanced: "55"
    case .higherQuality: "70"
    }
  }

  private static func jpegQuality(for quality: QualityPreset) -> String {
    switch quality {
    case .smaller: "8"
    case .balanced: "5"
    case .higherQuality: "2"
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
