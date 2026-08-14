import Foundation
import OptimizeAnythingCore

let ruleCatalogTests: [TestCase] = [
  TestCase("default rules match approved balanced profiles") {
    let rules = RuleCatalog.defaultRules

    try expectEqual(rules.count, 3)
    try expectEqual(rules[0].id, RuleCatalog.audioRuleID)
    try expectEqual(rules[0].family, .audio)
    try expectEqual(rules[0].sourceExtensions, ["wav", "aiff", "flac", "caf"])
    try expectEqual(rules[0].target, .m4a)
    try expectEqual(rules[0].quality, .balanced)
    try expectTrue(rules[0].isEnabled)

    try expectEqual(rules[1].id, RuleCatalog.videoRuleID)
    try expectEqual(rules[1].family, .video)
    try expectEqual(rules[1].sourceExtensions, ["mov", "mp4", "mkv"])
    try expectEqual(rules[1].target, .webm)
    try expectEqual(rules[1].quality, .balanced)
    try expectTrue(rules[1].isEnabled)

    try expectEqual(rules[2].id, RuleCatalog.imageRuleID)
    try expectEqual(rules[2].family, .image)
    try expectEqual(rules[2].sourceExtensions, ["jpeg", "jpg", "png", "webp", "tiff"])
    try expectEqual(rules[2].target, .avif)
    try expectEqual(rules[2].quality, .balanced)
    try expectTrue(rules[2].isEnabled)

    try expectEqual(try RuleValidator.validate(rules), rules)
  },
  TestCase("validator normalizes leading dots case and duplicates") {
    let rule = ConversionRule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
      family: .audio,
      sourceExtensions: [".WAV", " wav ", "AIFF"],
      target: .m4a,
      quality: .smaller,
      isEnabled: true
    )

    let validated = try RuleValidator.validate([rule])

    try expectEqual(validated[0].sourceExtensions, ["wav", "aiff"])
  },
  TestCase("validator rejects enabled extension conflict") {
    var rules = RuleCatalog.defaultRules
    rules.append(
      ConversionRule(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        family: .audio,
        sourceExtensions: [".WAV"],
        target: .m4a,
        quality: .smaller,
        isEnabled: true
      ))
    let conflictingRules = rules

    try await expectThrows(RuleValidationError.duplicateSourceExtension("wav")) {
      _ = try RuleValidator.validate(conflictingRules)
    }
  },
  TestCase("validator allows conflict when one rule is disabled") {
    var rules = RuleCatalog.defaultRules
    rules.append(
      ConversionRule(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        family: .audio,
        sourceExtensions: ["wav"],
        target: .m4a,
        quality: .smaller,
        isEnabled: false
      ))

    _ = try RuleValidator.validate(rules)
  },
  TestCase("validator rejects empty sources") {
    let rule = ConversionRule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
      family: .audio,
      sourceExtensions: [".", "  "],
      target: .m4a,
      quality: .balanced,
      isEnabled: true
    )

    try await expectThrows(RuleValidationError.emptySourceExtensions(ruleID: rule.id)) {
      _ = try RuleValidator.validate([rule])
    }
  },
  TestCase("validator rejects target from another family") {
    let rule = ConversionRule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
      family: .audio,
      sourceExtensions: ["wav"],
      target: .webm,
      quality: .balanced,
      isEnabled: true
    )

    try await expectThrows(RuleValidationError.incompatibleTarget(ruleID: rule.id)) {
      _ = try RuleValidator.validate([rule])
    }
  },
  TestCase("target compatibility is restricted by family") {
    try expectEqual(RuleCatalog.targets(for: .audio), [.m4a])
    try expectEqual(RuleCatalog.targets(for: .video), [.webm])
    try expectEqual(RuleCatalog.targets(for: .image), [.avif])
  },
]
