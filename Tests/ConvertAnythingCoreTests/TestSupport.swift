import ConvertAnythingCore
import Foundation

func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("convert-anything-tests", isDirectory: true)
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func fixtureFile(named name: String, bytes: Data = Data([1])) throws -> URL {
  let directory = try temporaryDirectory()
  let file = directory.appendingPathComponent(name)
  try bytes.write(to: file)
  return file
}

func makePlan(
  source: String,
  target: TargetFormat,
  quality: QualityPreset
) throws -> ConversionPlan {
  let input = try fixtureFile(named: source)
  let rule = ConversionRule(
    id: UUID(uuidString: "20000000-0000-0000-0000-000000000000")!,
    family: target.family,
    sourceExtensions: [input.pathExtension.lowercased()],
    target: target,
    quality: quality,
    isEnabled: true
  )
  let jobID = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
  let output = try OutputPathResolver().resolve(input: input, target: target, jobID: jobID)
  return ConversionPlan(id: jobID, input: input, output: output, rule: rule, sourceByteCount: 1)
}

func makePlan(for input: URL, target: TargetFormat, quality: QualityPreset = .balanced) throws
  -> ConversionPlan
{
  let rule = ConversionRule(
    id: UUID(uuidString: "20000000-0000-0000-0000-000000000000")!,
    family: target.family,
    sourceExtensions: [input.pathExtension.lowercased()],
    target: target,
    quality: quality,
    isEnabled: true
  )
  let jobID = UUID()
  let output = try OutputPathResolver().resolve(input: input, target: target, jobID: jobID)
  let byteCount = try FileManager.default.attributesOfItem(atPath: input.path)[.size] as? NSNumber
  return ConversionPlan(
    id: jobID,
    input: input,
    output: output,
    rule: rule,
    sourceByteCount: byteCount?.int64Value ?? 0
  )
}

extension InputMediaInfo {
  static let audioFixture = InputMediaInfo(
    containerNames: ["wav"],
    durationSeconds: 2,
    videoCodec: nil,
    audioCodec: "pcm_s16le",
    width: nil,
    height: nil,
    channelCount: 2,
    hasAlpha: false,
    rotationDegrees: nil
  )

  static let videoWithAudioFixture = InputMediaInfo(
    containerNames: ["mov", "mp4"],
    durationSeconds: 3,
    videoCodec: "vp9-placeholder",
    audioCodec: "aac",
    width: 320,
    height: 180,
    channelCount: 2,
    hasAlpha: false,
    rotationDegrees: 90
  )

  static let alphaImageFixture = InputMediaInfo(
    containerNames: ["png_pipe"],
    durationSeconds: nil,
    videoCodec: "png",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: true,
    rotationDegrees: nil
  )

  static let opaqueImageFixture = InputMediaInfo(
    containerNames: ["image2"],
    durationSeconds: nil,
    videoCodec: "mjpeg",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: false,
    rotationDegrees: nil
  )

  static let opaqueWebP = InputMediaInfo(
    containerNames: ["webp_pipe"],
    durationSeconds: nil,
    videoCodec: "webp",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: false,
    rotationDegrees: nil
  )

  static let alphaWebP = InputMediaInfo(
    containerNames: ["webp_pipe"],
    durationSeconds: nil,
    videoCodec: "webp",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: true,
    rotationDegrees: nil
  )

  static let mp3Output = InputMediaInfo(
    containerNames: ["mp3"],
    durationSeconds: 2,
    videoCodec: nil,
    audioCodec: "mp3",
    width: nil,
    height: nil,
    channelCount: 2,
    hasAlpha: false,
    rotationDegrees: nil
  )

  static let h264MP4 = InputMediaInfo(
    containerNames: ["mov", "mp4", "m4a", "3gp", "3g2", "mj2"],
    durationSeconds: 3,
    videoCodec: "h264",
    audioCodec: "aac",
    width: 320,
    height: 180,
    channelCount: 2,
    hasAlpha: false,
    rotationDegrees: 90
  )

  static let jpegOutput = InputMediaInfo(
    containerNames: ["image2"],
    durationSeconds: nil,
    videoCodec: "mjpeg",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: false,
    rotationDegrees: nil
  )

  static let alphaPNGOutput = InputMediaInfo(
    containerNames: ["png_pipe"],
    durationSeconds: nil,
    videoCodec: "png",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: true,
    rotationDegrees: nil
  )

  static let aacM4A = InputMediaInfo(
    containerNames: ["mov", "mp4", "m4a"],
    durationSeconds: 2,
    videoCodec: nil,
    audioCodec: "aac",
    width: nil,
    height: nil,
    channelCount: 2,
    hasAlpha: false,
    rotationDegrees: nil
  )

  static let vp9OpusWebM = InputMediaInfo(
    containerNames: ["matroska", "webm"],
    durationSeconds: 3,
    videoCodec: "vp9",
    audioCodec: "opus",
    width: 320,
    height: 180,
    channelCount: 2,
    hasAlpha: false,
    rotationDegrees: 90
  )

  static let opaqueAVIF = InputMediaInfo(
    containerNames: ["avif"],
    durationSeconds: nil,
    videoCodec: "av1",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: false,
    rotationDegrees: nil
  )

  static let alphaAVIF = InputMediaInfo(
    containerNames: ["avif"],
    durationSeconds: nil,
    videoCodec: "av1",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: true,
    rotationDegrees: nil
  )
}
