import Foundation
import ImageIO

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
      arguments: [
        "-v", "error", "-show_format", "-show_streams", "-show_stream_groups", "-of", "json",
        input.path,
      ]
    )
    let result = try await executor.execute(request) { _ in }
    guard result.terminationStatus == 0 else {
      throw MediaProbeError.rejected(result.lastStandardErrorLine(fallback: "Media probe failed"))
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
    let heicBrands = ["heic", "heix", "hevc", "hevx"]
    let isHEIC =
      majorBrand.map(heicBrands.contains) ?? false
      || heicBrands.contains(where: compatibleBrands.contains)
    if !containerNames.contains("heic") && isHEIC {
      containerNames.append("heic")
    }
    let videoStreams = response.streams.filter { $0.codecType == "video" }
    let video = videoStreams.first
    let audio = response.streams.first { $0.codecType == "audio" }
    let pixelFormat = video?.pixelFormat?.lowercased() ?? ""
    let formatsWithAlpha = ["rgba", "bgra", "argb", "abgr"]
    let hasPixelAlpha = formatsWithAlpha.contains(pixelFormat) || pixelFormat.contains("yuva")
    let isHEIFImage = containerNames.contains("avif") || containerNames.contains("heic")
    let parsedGrids = heifGrids(from: response.streamGroups)
    let colorGrid =
      parsedGrids.first(where: { $0.isDefault && !$0.isAlpha })?.grid
      ?? parsedGrids.first(where: { !$0.isAlpha })?.grid
    let alphaGrid = colorGrid.flatMap { color in
      parsedGrids.first(where: {
        $0.isAlpha && $0.grid.width == color.width && $0.grid.height == color.height
      })?.grid
    }
    let referenceWidth = colorGrid?.width ?? video?.width
    let referenceHeight = colorGrid?.height ?? video?.height
    let auxiliaryAlphaVideoStreamIndex =
      isHEIFImage && alphaGrid == nil
      ? videoStreams.enumerated().dropFirst().first { _, stream in
        let auxiliaryPixelFormat = stream.pixelFormat?.lowercased() ?? ""
        return auxiliaryPixelFormat.hasPrefix("gray")
          && stream.width == referenceWidth
          && stream.height == referenceHeight
      }?.offset : nil
    let orientation = colorGrid == nil ? 1 : heicOrientation(at: input)
    let swapsAxes = [5, 6, 7, 8].contains(orientation)
    let width = swapsAxes ? referenceHeight : referenceWidth
    let height = swapsAxes ? referenceWidth : referenceHeight
    let rotation =
      video?.sideData?.compactMap(\.rotation).first
      ?? video?.tags?["rotate"].flatMap(Int.init)

    return InputMediaInfo(
      containerNames: containerNames,
      durationSeconds: response.format?.duration.flatMap(Double.init),
      videoCodec: video?.codecName?.lowercased(),
      audioCodec: audio?.codecName?.lowercased(),
      width: width,
      height: height,
      channelCount: audio?.channels,
      hasAlpha: hasPixelAlpha || auxiliaryAlphaVideoStreamIndex != nil || alphaGrid != nil,
      rotationDegrees: rotation,
      auxiliaryAlphaVideoStreamIndex: auxiliaryAlphaVideoStreamIndex,
      heicColorGrid: colorGrid,
      heicAlphaGrid: alphaGrid,
      heicOrientation: orientation
    )
  }

  private func heifGrids(from groups: [ProbeStreamGroup]) -> [ParsedHEIFGrid] {
    groups.compactMap { group in
      guard group.type == "Tile Grid",
        let component = group.components?.first,
        let codedWidth = component.codedWidth, codedWidth > 0,
        let codedHeight = component.codedHeight, codedHeight > 0,
        let width = component.width, width > 0,
        let height = component.height, height > 0,
        let placements = component.tiles, !placements.isEmpty
      else {
        return nil
      }
      let members = group.streams ?? []
      var tiles: [HEICTilePlacement] = []
      for placement in placements {
        guard let localIndex = placement.streamIndex,
          members.indices.contains(localIndex),
          let streamIndex = members[localIndex].index,
          let x = placement.x, x >= 0,
          let y = placement.y, y >= 0
        else {
          return nil
        }
        tiles.append(HEICTilePlacement(streamIndex: streamIndex, x: x, y: y))
      }
      let grid = HEICImageGrid(
        codedWidth: codedWidth,
        codedHeight: codedHeight,
        originX: max(0, component.horizontalOffset ?? 0),
        originY: max(0, component.verticalOffset ?? 0),
        width: width,
        height: height,
        tiles: tiles
      )
      let isAlpha =
        !members.isEmpty
        && members.allSatisfy { ($0.pixelFormat?.lowercased() ?? "").hasPrefix("gray") }
      return ParsedHEIFGrid(
        isDefault: group.disposition?.isDefault == 1,
        isAlpha: isAlpha,
        grid: grid
      )
    }
  }

  /// ImageIO reports the orientation of the derived HEIC image. FFmpeg 8.0
  /// does not put that display matrix on the tile streams.
  private func heicOrientation(at url: URL) -> Int {
    guard FileManager.default.fileExists(atPath: url.path),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      return 1
    }
    return integerOrientation(properties[kCGImagePropertyOrientation]) ?? 1
  }

  private func integerOrientation(_ value: Any?) -> Int? {
    let number: Int?
    switch value {
    case let value as UInt32:
      number = Int(value)
    case let value as Int:
      number = value
    case let value as NSNumber:
      number = value.intValue
    default:
      number = nil
    }
    guard let number, (1...8).contains(number) else { return nil }
    return number
  }
}

private struct ParsedHEIFGrid {
  let isDefault: Bool
  let isAlpha: Bool
  let grid: HEICImageGrid
}

private struct ProbeResponse: Decodable {
  let format: ProbeFormat?
  let streams: [ProbeStream]
  let streamGroups: [ProbeStreamGroup]

  private enum CodingKeys: String, CodingKey {
    case format
    case streams
    case streamGroups = "stream_groups"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    format = try container.decodeIfPresent(ProbeFormat.self, forKey: .format)
    streams = try container.decodeIfPresent([ProbeStream].self, forKey: .streams) ?? []
    streamGroups =
      try container.decodeIfPresent([ProbeStreamGroup].self, forKey: .streamGroups) ?? []
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
  let index: Int?
  let codecType: String?
  let codecName: String?
  let pixelFormat: String?
  let width: Int?
  let height: Int?
  let channels: Int?
  let tags: [String: String]?
  let sideData: [ProbeSideData]?

  private enum CodingKeys: String, CodingKey {
    case index
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

private struct ProbeStreamGroup: Decodable {
  let type: String?
  let disposition: ProbeDisposition?
  let components: [ProbeTileGridComponent]?
  let streams: [ProbeStream]?
}

private struct ProbeDisposition: Decodable {
  let isDefault: Int?

  private enum CodingKeys: String, CodingKey {
    case isDefault = "default"
  }
}

private struct ProbeTileGridComponent: Decodable {
  let codedWidth: Int?
  let codedHeight: Int?
  let horizontalOffset: Int?
  let verticalOffset: Int?
  let width: Int?
  let height: Int?
  let tiles: [ProbeTileOffset]?

  private enum CodingKeys: String, CodingKey {
    case codedWidth = "coded_width"
    case codedHeight = "coded_height"
    case horizontalOffset = "horizontal_offset"
    case verticalOffset = "vertical_offset"
    case width
    case height
    case tiles = "subcomponents"
  }
}

private struct ProbeTileOffset: Decodable {
  let streamIndex: Int?
  let x: Int?
  let y: Int?

  private enum CodingKeys: String, CodingKey {
    case streamIndex = "stream_index"
    case x = "tile_horizontal_offset"
    case y = "tile_vertical_offset"
  }
}

private struct ProbeSideData: Decodable {
  let rotation: Int?
}
