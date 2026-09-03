import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

let ruleCatalogTests: [TestCase] = [
  TestCase("default rules match approved balanced profiles") {
    let rules = RuleCatalog.defaultRules

    try expectEqual(rules.count, 7)
    try expectEqual(rules.map(\.id).count, Set(rules.map(\.id)).count)
    for rule in rules {
      try expectEqual(rule.quality, .balanced)
      try expectTrue(rule.isEnabled)
    }

    try expectEqual(rules[0].id, RuleCatalog.audioRuleID)
    try expectEqual(rules[0].family, .audio)
    try expectEqual(rules[0].sourceExtensions, ["wav", "aiff", "flac", "caf"])
    try expectEqual(rules[0].target, .m4a)

    try expectEqual(rules[1].id, RuleCatalog.mp3AudioRuleID)
    try expectEqual(rules[1].family, .audio)
    try expectEqual(rules[1].sourceExtensions, ["m4a"])
    try expectEqual(rules[1].target, .mp3)

    try expectEqual(rules[2].id, RuleCatalog.videoRuleID)
    try expectEqual(rules[2].family, .video)
    try expectEqual(rules[2].sourceExtensions, ["mov", "mp4", "mkv"])
    try expectEqual(rules[2].target, .webm)

    try expectEqual(rules[3].id, RuleCatalog.mp4VideoRuleID)
    try expectEqual(rules[3].family, .video)
    try expectEqual(rules[3].sourceExtensions, ["webm"])
    try expectEqual(rules[3].target, .mp4)

    try expectEqual(rules[4].id, RuleCatalog.imageRuleID)
    try expectEqual(rules[4].family, .image)
    try expectEqual(rules[4].sourceExtensions, ["jpeg", "jpg", "png", "tiff"])
    try expectEqual(rules[4].target, .avif)

    try expectEqual(rules[5].id, RuleCatalog.webpImageRuleID)
    try expectEqual(rules[5].family, .image)
    try expectEqual(rules[5].sourceExtensions, ["webp"])
    try expectEqual(rules[5].target, .jpegOrPng)

    try expectEqual(rules[6].family, .image)
    try expectEqual(rules[6].id, RuleCatalog.heicImageRuleID)
    try expectEqual(rules[6].sourceExtensions, ["heic"])
    try expectEqual(rules[6].target, .jpegOrPng)

    try expectEqual(try RuleValidator.validate(rules), rules)
  },
  TestCase("reverse-rule migration frees webp and adds unclaimed defaults") {
    var storedRules = [
      RuleCatalog.defaultRules[0],
      RuleCatalog.defaultRules[2],
      ConversionRule(
        id: RuleCatalog.imageRuleID,
        family: .image,
        sourceExtensions: ["jpeg", "jpg", "png", "webp", "tiff"],
        target: .avif,
        quality: .higherQuality,
        isEnabled: true
      ),
    ]
    storedRules[0].quality = .smaller

    let migrated = RuleCatalog.addingReverseRules(to: storedRules)

    try expectEqual(migrated.count, 6)
    try expectEqual(migrated[0].quality, .smaller)
    try expectEqual(migrated[2].sourceExtensions, ["jpeg", "jpg", "png", "tiff"])
    try expectEqual(migrated[2].quality, .higherQuality)
    try expectEqual(migrated[3].id, RuleCatalog.mp3AudioRuleID)
    try expectEqual(migrated[4].id, RuleCatalog.mp4VideoRuleID)
    try expectEqual(migrated[5].id, RuleCatalog.webpImageRuleID)
    _ = try RuleValidator.validate(migrated)
  },
  TestCase("reverse-rule migration skips defaults whose extensions are claimed") {
    let customRule = ConversionRule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
      family: .audio,
      sourceExtensions: ["m4a"],
      target: .mp3,
      quality: .smaller,
      isEnabled: true
    )

    let migrated = RuleCatalog.addingReverseRules(to: [customRule])

    try expectEqual(
      migrated.map(\.id),
      [customRule.id, RuleCatalog.mp4VideoRuleID, RuleCatalog.webpImageRuleID]
    )
    try expectEqual(migrated[0].quality, .smaller)
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
    try expectEqual(RuleCatalog.targets(for: .audio), [.m4a, .mp3])
    try expectEqual(RuleCatalog.targets(for: .video), [.webm, .mp4])
    try expectEqual(RuleCatalog.targets(for: .image), [.avif, .jpegOrPng])
  },
  TestCase("dynamic image target resolves extension by alpha") {
    try expectEqual(TargetFormat.jpegOrPng.fileExtension(hasAlpha: false), "jpg")
    try expectEqual(TargetFormat.jpegOrPng.fileExtension(hasAlpha: true), "png")
    try expectEqual(TargetFormat.mp4.fileExtension(hasAlpha: true), "mp4")
    try expectEqual(TargetFormat.jpegOrPng.displayName, "JPG/PNG")
  },
]
