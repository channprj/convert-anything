import Foundation

public enum MediaProbeError: Error, Equatable, Sendable {
  case rejected(String)
  case invalidResponse
}

public struct FFprobeClient: Sendable {
  private let executable: URL
  private let executor: any CommandExecuting

  public init(executable: URL, executor: any CommandExecuting) {
    self.executable = executable
    self.executor = executor
  }

  public func probe(_ input: URL, commandID: UUID) async throws -> InputMediaInfo {
    let request = CommandRequest(
      id: commandID,
      executable: executable,
      arguments: ["-v", "error", "-show_format", "-show_streams", "-of", "json", input.path]
    )
    let result = try await executor.execute(request) { _ in }
    guard result.terminationStatus == 0 else {
      throw MediaProbeError.rejected(Self.lastRelevantLine(in: result.standardError))
    }

    let response: ProbeResponse
    do {
      response = try JSONDecoder().decode(ProbeResponse.self, from: result.standardOutput)
    } catch {
      throw MediaProbeError.invalidResponse
    }

    var containerNames =
      response.format?.formatName?
      .split(separator: ",")
      .map { String($0).lowercased() } ?? []
    let formatTags = response.format?.tags ?? [:]
    let majorBrand = formatTags["major_brand"]?.lowercased()
    let compatibleBrands = formatTags["compatible_brands"]?.lowercased() ?? ""
    if !containerNames.contains("avif")
      && (majorBrand == "avif" || compatibleBrands.contains("avif"))
    {
      containerNames.append("avif")
    }
    let videoStreams = response.streams.filter { $0.codecType == "video" }
    let video = videoStreams.first
    let audio = response.streams.first { $0.codecType == "audio" }
    let pixelFormat = video?.pixelFormat?.lowercased() ?? ""
    let formatsWithAlpha = ["rgba", "bgra", "argb", "abgr"]
    let hasPixelAlpha = formatsWithAlpha.contains(pixelFormat) || pixelFormat.contains("yuva")
    let hasAuxiliaryAlpha = containerNames.contains("avif") && videoStreams.count > 1
    let rotation =
      video?.sideData?.compactMap(\.rotation).first
      ?? video?.tags?["rotate"].flatMap(Int.init)

    return InputMediaInfo(
      containerNames: containerNames,
      durationSeconds: response.format?.duration.flatMap(Double.init),
      videoCodec: video?.codecName?.lowercased(),
      audioCodec: audio?.codecName?.lowercased(),
      width: video?.width,
      height: video?.height,
      channelCount: audio?.channels,
      hasAlpha: hasPixelAlpha || hasAuxiliaryAlpha,
      rotationDegrees: rotation
    )
  }

  private static func lastRelevantLine(in data: Data) -> String {
    String(decoding: data, as: UTF8.self)
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .last ?? "Media probe failed"
  }
}

private struct ProbeResponse: Decodable {
  let format: ProbeFormat?
  let streams: [ProbeStream]

  private enum CodingKeys: String, CodingKey {
    case format
    case streams
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    format = try container.decodeIfPresent(ProbeFormat.self, forKey: .format)
    streams = try container.decodeIfPresent([ProbeStream].self, forKey: .streams) ?? []
  }
}

private struct ProbeFormat: Decodable {
  let formatName: String?
  let duration: String?
  let tags: [String: String]?

  private enum CodingKeys: String, CodingKey {
    case formatName = "format_name"
    case duration
    case tags
  }
}

private struct ProbeStream: Decodable {
  let codecType: String?
  let codecName: String?
  let pixelFormat: String?
  let width: Int?
  let height: Int?
  let channels: Int?
  let tags: [String: String]?
  let sideData: [ProbeSideData]?

  private enum CodingKeys: String, CodingKey {
    case codecType = "codec_type"
    case codecName = "codec_name"
    case pixelFormat = "pix_fmt"
    case width
    case height
    case channels
    case tags
    case sideData = "side_data_list"
  }
}

private struct ProbeSideData: Decodable {
  let rotation: Int?
}
