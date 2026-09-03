import Foundation

public enum RuleCatalog {
  public static let audioRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  public static let videoRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  public static let imageRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
  public static let mp3AudioRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
  public static let mp4VideoRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
  public static let webpImageRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
  public static let heicImageRuleID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!

  private static let heicRule = ConversionRule(
    id: heicImageRuleID,
    family: .image,
    sourceExtensions: ["heic"],
    target: .jpegOrPng,
    quality: .balanced,
    isEnabled: true
  )

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
      id: mp3AudioRuleID,
      family: .audio,
      sourceExtensions: ["m4a"],
      target: .mp3,
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
      id: mp4VideoRuleID,
      family: .video,
      sourceExtensions: ["webm"],
      target: .mp4,
      quality: .balanced,
      isEnabled: true
    ),
    ConversionRule(
      id: imageRuleID,
      family: .image,
      sourceExtensions: ["jpeg", "jpg", "png", "tiff"],
      target: .avif,
      quality: .balanced,
      isEnabled: true
    ),
    ConversionRule(
      id: webpImageRuleID,
      family: .image,
      sourceExtensions: ["webp"],
      target: .jpegOrPng,
      quality: .balanced,
      isEnabled: true
    ),
    heicRule,
  ]

  public static func targets(for family: MediaFamily) -> [TargetFormat] {
    TargetFormat.allCases.filter { $0.family == family }
  }

  /// Schema 1 → 2 migration: free the webp extension from AVIF rules and
  /// add the reverse-direction defaults whose extensions are still unclaimed.
  public static func addingReverseRules(to rules: [ConversionRule]) -> [ConversionRule] {
    var migrated = rules
    for index in migrated.indices
    where migrated[index].target == .avif && migrated[index].sourceExtensions.count > 1 {
      migrated[index].sourceExtensions.removeAll { $0 == "webp" }
    }

    let claimed = Set(migrated.filter(\.isEnabled).flatMap(\.sourceExtensions))
    let reverseRuleIDs: Set<UUID> = [mp3AudioRuleID, mp4VideoRuleID, webpImageRuleID]
    for rule in defaultRules
    where reverseRuleIDs.contains(rule.id) && claimed.isDisjoint(with: rule.sourceExtensions) {
      migrated.append(rule)
    }
    return migrated
  }

  /// Schema 2 → 3 migration: add the HEIC default when no enabled rule
  /// already owns the extension.
  public static func addingHEICRule(to rules: [ConversionRule]) -> [ConversionRule] {
    let claimed = Set(
      RuleValidator.normalize(rules.filter(\.isEnabled).flatMap(\.sourceExtensions))
    )
    guard !claimed.contains("heic") else { return rules }

    var migrated = rules
    migrated.append(heicRule)
    return migrated
  }
}
