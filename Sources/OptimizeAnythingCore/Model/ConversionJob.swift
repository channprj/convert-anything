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

  public init(
    containerNames: [String],
    durationSeconds: Double?,
    videoCodec: String?,
    audioCodec: String?,
    width: Int?,
    height: Int?,
    channelCount: Int?,
    hasAlpha: Bool,
    rotationDegrees: Int?
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
  }
}

public enum PlanningError: Error, Equatable, Sendable {
  case inputUnavailable
  case insufficientDiskSpace(required: Int64, available: Int64)
  case noEnabledRule(String)
}
