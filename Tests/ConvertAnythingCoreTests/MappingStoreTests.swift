import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

let mappingStoreTests: [TestCase] = [
  TestCase("missing settings file loads and persists approved defaults") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("nested/settings.json")
    let store = MappingStore(fileURL: url)

    let document = try await store.load()

    try expectEqual(
      document,
      SettingsDocument(schemaVersion: 2, rules: RuleCatalog.defaultRules)
    )
    try expectTrue(FileManager.default.fileExists(atPath: url.path))
    let persisted = try JSONDecoder().decode(SettingsDocument.self, from: Data(contentsOf: url))
    try expectEqual(persisted, document)
  },
  TestCase("saved intentional quality choice survives reload") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    let store = MappingStore(fileURL: url)
    var document = try await store.load()
    document.rules[0].quality = .higherQuality

    try await store.save(document)
    let reloaded = try await store.load()

    try expectEqual(reloaded.rules[0].quality, .higherQuality)
  },
  TestCase("invalid save leaves last valid settings bytes untouched") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    let store = MappingStore(fileURL: url)
    _ = try await store.load()
    let before = try Data(contentsOf: url)
    var invalidRules = RuleCatalog.defaultRules
    invalidRules.append(invalidRules[0])
    let invalid = SettingsDocument(rules: invalidRules)

    try await expectThrows(RuleValidationError.duplicateSourceExtension("wav")) {
      try await store.save(invalid)
    }

    try expectEqual(try Data(contentsOf: url), before)
  },
  TestCase("schema zero migrates once without rewriting user fields") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    var rules = RuleCatalog.defaultRules
    rules[1].quality = .smaller
    rules[2].isEnabled = false
    let legacy = SettingsDocument(schemaVersion: 0, rules: rules)
    try JSONEncoder().encode(legacy).write(to: url)
    let store = MappingStore(fileURL: url)

    let firstLoad = try await store.load()
    let firstBytes = try Data(contentsOf: url)
    let secondLoad = try await store.load()

    try expectEqual(firstLoad.schemaVersion, 2)
    try expectEqual(firstLoad.rules, rules)
    try expectEqual(secondLoad, firstLoad)
    try expectEqual(try Data(contentsOf: url), firstBytes)
  },
  TestCase("schema one gains the reverse rules once") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    let legacyRules = [
      RuleCatalog.defaultRules[0],
      RuleCatalog.defaultRules[2],
      ConversionRule(
        id: RuleCatalog.imageRuleID,
        family: .image,
        sourceExtensions: ["jpeg", "jpg", "png", "webp", "tiff"],
        target: .avif,
        quality: .balanced,
        isEnabled: true
      ),
    ]
    let legacy = SettingsDocument(schemaVersion: 1, rules: legacyRules)
    try JSONEncoder().encode(legacy).write(to: url)
    let store = MappingStore(fileURL: url)

    let firstLoad = try await store.load()
    let firstBytes = try Data(contentsOf: url)
    let secondLoad = try await store.load()

    try expectEqual(firstLoad.schemaVersion, 2)
    try expectEqual(firstLoad.rules.count, 6)
    try expectEqual(firstLoad.rules[2].sourceExtensions, ["jpeg", "jpg", "png", "tiff"])
    try expectEqual(
      firstLoad.rules[3...].map(\.id),
      [RuleCatalog.mp3AudioRuleID, RuleCatalog.mp4VideoRuleID, RuleCatalog.webpImageRuleID]
    )
    try expectEqual(secondLoad, firstLoad)
    try expectEqual(try Data(contentsOf: url), firstBytes)
  },
  TestCase("future settings schema is rejected without rewriting bytes") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    let future = SettingsDocument(schemaVersion: 3, rules: RuleCatalog.defaultRules)
    let bytes = try JSONEncoder().encode(future)
    try bytes.write(to: url)
    let store = MappingStore(fileURL: url)

    try await expectThrows(RuleValidationError.unsupportedSchemaVersion(3)) {
      _ = try await store.load()
    }

    try expectEqual(try Data(contentsOf: url), bytes)
  },
  TestCase("save persists normalized extensions rather than raw editor input") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    let store = MappingStore(fileURL: url)
    let rawRule = ConversionRule(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
      family: .audio,
      sourceExtensions: [".WAV", " AIF "],
      target: .m4a,
      quality: .balanced,
      isEnabled: true
    )

    try await store.save(SettingsDocument(rules: [rawRule]))
    let reloaded = try await store.load()

    try expectEqual(reloaded.rules[0].sourceExtensions, ["wav", "aif"])
  },
]
