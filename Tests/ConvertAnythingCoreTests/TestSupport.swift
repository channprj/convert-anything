import ConvertAnythingCore
import ConvertAnythingTestSupport
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
  try makePlan(for: fixtureFile(named: source), target: target, quality: quality)
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

  static let alphaHEIC = InputMediaInfo(
    containerNames: ["mov", "mp4", "heic"],
    durationSeconds: nil,
    videoCodec: "hevc",
    audioCodec: nil,
    width: 96,
    height: 64,
    channelCount: nil,
    hasAlpha: true,
    rotationDegrees: nil,
    auxiliaryAlphaVideoStreamIndex: 2
  )

  /// Output-side twins of the input fixtures; aliases keep call sites
  /// intent-revealing while guaranteeing the data cannot drift apart.
  static let jpegOutput = opaqueImageFixture
  static let alphaPNGOutput = alphaImageFixture

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
}

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
}

func commandResult(for info: InputMediaInfo) -> CommandResult {
  CommandResult(
    terminationStatus: 0,
    standardOutput: probeJSON(for: info),
    standardError: Data()
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
