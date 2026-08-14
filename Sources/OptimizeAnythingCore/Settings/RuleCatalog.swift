import Foundation

public enum RuleCatalog {
  public static let audioRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  public static let videoRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  public static let imageRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

  public static let defaultRules: [ConversionRule] = [
    ConversionRule(
      id: audioRuleID,
      family: .audio,
      sourceExtensions: ["wav", "aiff", "flac", "caf"],
      target: .m4a,
      quality: .balanced,
      isEnabled: true
    ),
    ConversionRule(
      id: videoRuleID,
      family: .video,
      sourceExtensions: ["mov", "mp4", "mkv"],
      target: .webm,
      quality: .balanced,
      isEnabled: true
    ),
    ConversionRule(
      id: imageRuleID,
      family: .image,
      sourceExtensions: ["jpeg", "jpg", "png", "webp", "tiff"],
      target: .avif,
      quality: .balanced,
      isEnabled: true
    ),
  ]

  public static func targets(for family: MediaFamily) -> [TargetFormat] {
    TargetFormat.allCases.filter { $0.family == family }
  }
}
