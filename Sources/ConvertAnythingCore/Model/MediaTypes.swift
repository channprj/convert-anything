public enum MediaFamily: String, Codable, CaseIterable, Sendable {
  case audio
  case video
  case image
}

public enum TargetFormat: String, Codable, CaseIterable, Sendable {
  case m4a
  case mp3
  case webm
  case mp4
  case avif
  case jpegOrPng = "jpeg-or-png"

  public var family: MediaFamily {
    switch self {
    case .m4a, .mp3:
      .audio
    case .webm, .mp4:
      .video
    case .avif, .jpegOrPng:
      .image
    }
  }

  public var displayName: String {
    switch self {
    case .jpegOrPng:
      "JPG/PNG"
    default:
      rawValue.uppercased()
    }
  }

  /// Output extension for a probed input; jpegOrPng keeps PNG only when
  /// the source carries alpha, and JPEG otherwise for the smaller file.
  public func fileExtension(hasAlpha: Bool) -> String {
    switch self {
    case .jpegOrPng:
      hasAlpha ? "png" : "jpg"
    default:
      rawValue
    }
  }
}

public enum QualityPreset: String, Codable, CaseIterable, Sendable {
  case smaller
  case balanced
  case higherQuality
}
