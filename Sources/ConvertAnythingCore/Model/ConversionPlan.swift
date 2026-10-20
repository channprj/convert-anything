import Foundation

public struct AdmissionDecision: Equatable, Sendable {
  public let input: URL
  public let status: AdmissionStatus

  public init(input: URL, status: AdmissionStatus) {
    self.input = input
    self.status = status
  }
}

public enum AdmissionError: Error, Equatable, Sendable {
  case missingFile
  case notRegularFile
  case unreadableFile
  case missingExtension
  case unsupportedExtension(String)
}

public enum AdmissionStatus: Equatable, Sendable {
  case accepted(ruleID: UUID)
  case rejected(AdmissionError)
}

public struct OutputPaths: Equatable, Sendable {
  public let final: URL
  public let temporary: URL

  public init(final: URL, temporary: URL) {
    self.final = final
    self.temporary = temporary
  }
}

public struct ConversionPlan: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let input: URL
  public let output: OutputPaths
  public let rule: ConversionRule
  public let sourceByteCount: Int64

  public init(
    id: UUID,
    input: URL,
    output: OutputPaths,
    rule: ConversionRule,
    sourceByteCount: Int64
  ) {
    self.id = id
    self.input = input
    self.output = output
    self.rule = rule
    self.sourceByteCount = sourceByteCount
  }
}

/// One tile of a HEIF derived image, addressed by its absolute stream index.
public struct HEICTilePlacement: Equatable, Sendable {
  public let streamIndex: Int
  public let x: Int
  public let y: Int

  public init(streamIndex: Int, x: Int, y: Int) {
    self.streamIndex = streamIndex
    self.x = x
    self.y = y
  }
}

/// A HEIF grid or overlay before display orientation is applied.
///
/// `width` and `height` are the clean image inside the coded canvas.
/// FFmpeg 8.0 exposes each tile as its own stream, so the coded canvas is
/// larger than one tile and often larger than the clean image.
public struct HEICImageGrid: Equatable, Sendable {
  public let codedWidth: Int
  public let codedHeight: Int
  public let originX: Int
  public let originY: Int
  public let width: Int
  public let height: Int
  public let tiles: [HEICTilePlacement]

  public init(
    codedWidth: Int,
    codedHeight: Int,
    originX: Int,
    originY: Int,
    width: Int,
    height: Int,
    tiles: [HEICTilePlacement]
  ) {
    self.codedWidth = codedWidth
    self.codedHeight = codedHeight
    self.originX = originX
    self.originY = originY
    self.width = width
    self.height = height
    self.tiles = tiles
  }

  public var needsCrop: Bool {
    originX != 0 || originY != 0 || width != codedWidth || height != codedHeight
  }
}

public struct InputMediaInfo: Equatable, Sendable {
  public let containerNames: [String]
  public let durationSeconds: Double?
  public let videoCodec: String?
  public let audioCodec: String?
  public let width: Int?
  public let height: Int?
  public let channelCount: Int?
  public let hasAlpha: Bool
  public let rotationDegrees: Int?
  public let auxiliaryAlphaVideoStreamIndex: Int?
  public let heicColorGrid: HEICImageGrid?
  public let heicAlphaGrid: HEICImageGrid?
  /// EXIF/ImageIO orientation of a tiled HEIC, or 1 when the pixels are already upright.
  public let heicOrientation: Int

  public init(
    containerNames: [String],
    durationSeconds: Double?,
    videoCodec: String?,
    audioCodec: String?,
    width: Int?,
    height: Int?,
    channelCount: Int?,
    hasAlpha: Bool,
    rotationDegrees: Int?,
    auxiliaryAlphaVideoStreamIndex: Int? = nil,
    heicColorGrid: HEICImageGrid? = nil,
    heicAlphaGrid: HEICImageGrid? = nil,
    heicOrientation: Int = 1
  ) {
    self.containerNames = containerNames
    self.durationSeconds = durationSeconds
    self.videoCodec = videoCodec
    self.audioCodec = audioCodec
    self.width = width
    self.height = height
    self.channelCount = channelCount
    self.hasAlpha = hasAlpha
    self.rotationDegrees = rotationDegrees
    self.auxiliaryAlphaVideoStreamIndex = auxiliaryAlphaVideoStreamIndex
    self.heicColorGrid = heicColorGrid
    self.heicAlphaGrid = heicAlphaGrid
    self.heicOrientation = heicOrientation
  }
}

public enum PlanningError: Error, Equatable, Sendable {
  case inputUnavailable
  case insufficientDiskSpace(required: Int64, available: Int64)
  case noEnabledRule(String)
}
