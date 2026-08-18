public enum MediaFamily: String, Codable, CaseIterable, Sendable {
  case audio
  case video
  case image
}

public enum TargetFormat: String, Codable, CaseIterable, Sendable {
  case m4a
  case webm
  case avif

  public var family: MediaFamily {
    switch self {
    case .m4a:
      .audio
    case .webm:
      .video
    case .avif:
      .image
    }
  }
}

public enum QualityPreset: String, Codable, CaseIterable, Sendable {
  case smaller
  case balanced
  case higherQuality
}
