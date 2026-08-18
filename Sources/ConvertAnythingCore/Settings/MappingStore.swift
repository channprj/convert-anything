import Foundation

public protocol SettingsServing: Sendable {
  func load() async throws -> SettingsDocument
  func save(_ document: SettingsDocument) async throws
}

public actor MappingStore: SettingsServing {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() async throws -> SettingsDocument {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      let defaults = SettingsDocument(rules: RuleCatalog.defaultRules)
      try persist(defaults)
      return defaults
    }

    let data = try Data(contentsOf: fileURL)
    let decoded = try JSONDecoder().decode(SettingsDocument.self, from: data)
    let migrated = try Self.migrate(decoded)
    let validated = SettingsDocument(
      schemaVersion: migrated.schemaVersion,
      rules: try RuleValidator.validate(migrated.rules)
    )

    if validated != decoded {
      try persist(validated)
    }
    return validated
  }

  public func save(_ document: SettingsDocument) async throws {
    let migrated = try Self.migrate(document)
    let validated = SettingsDocument(
      schemaVersion: migrated.schemaVersion,
      rules: try RuleValidator.validate(migrated.rules)
    )
    try persist(validated)
  }

  public nonisolated static func migrate(_ document: SettingsDocument) throws -> SettingsDocument {
    guard document.schemaVersion >= 0,
      document.schemaVersion <= SettingsDocument.currentSchemaVersion
    else {
      throw RuleValidationError.unsupportedSchemaVersion(document.schemaVersion)
    }

    var migrated = document
    if migrated.schemaVersion == 0 {
      migrated.schemaVersion = 1
    }
    if migrated.schemaVersion == 1 {
      migrated.rules = RuleCatalog.addingReverseRules(to: migrated.rules)
      migrated.schemaVersion = 2
    }
    return migrated
  }

  private func persist(_ document: SettingsDocument) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(document)
    try data.write(to: fileURL, options: .atomic)
  }
}
