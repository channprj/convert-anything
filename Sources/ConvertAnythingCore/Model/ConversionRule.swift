import Foundation

public struct ConversionRule: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var family: MediaFamily
  public var sourceExtensions: [String]
  public var target: TargetFormat
  public var quality: QualityPreset
  public var isEnabled: Bool

  public init(
    id: UUID,
    family: MediaFamily,
    sourceExtensions: [String],
    target: TargetFormat,
    quality: QualityPreset,
    isEnabled: Bool
  ) {
    self.id = id
    self.family = family
    self.sourceExtensions = sourceExtensions
    self.target = target
    self.quality = quality
    self.isEnabled = isEnabled
  }
}

public struct SettingsDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 3

  public var schemaVersion: Int
  public var rules: [ConversionRule]

  public init(schemaVersion: Int = currentSchemaVersion, rules: [ConversionRule]) {
    self.schemaVersion = schemaVersion
    self.rules = rules
  }
}

public enum RuleValidationError: Error, Equatable, Sendable {
  case emptySourceExtensions(ruleID: UUID)
  case incompatibleTarget(ruleID: UUID)
  case duplicateSourceExtension(String)
  case unsupportedSchemaVersion(Int)
}

public enum RuleValidator {
  public static func validate(_ rules: [ConversionRule]) throws -> [ConversionRule] {
    var claimedExtensions = Set<String>()
    var validated: [ConversionRule] = []
    validated.reserveCapacity(rules.count)

    for var rule in rules {
      guard rule.target.family == rule.family else {
        throw RuleValidationError.incompatibleTarget(ruleID: rule.id)
      }

      rule.sourceExtensions = normalize(rule.sourceExtensions)
      guard !rule.sourceExtensions.isEmpty else {
        throw RuleValidationError.emptySourceExtensions(ruleID: rule.id)
      }

      if rule.isEnabled {
        for sourceExtension in rule.sourceExtensions {
          guard claimedExtensions.insert(sourceExtension).inserted else {
            throw RuleValidationError.duplicateSourceExtension(sourceExtension)
          }
        }
      }

      validated.append(rule)
    }

    return validated
  }

  static func normalize(_ sourceExtensions: [String]) -> [String] {
    var seen = Set<String>()
    var normalized: [String] = []

    for value in sourceExtensions {
      var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      while candidate.hasPrefix(".") {
        candidate.removeFirst()
      }
      candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

      guard !candidate.isEmpty, seen.insert(candidate).inserted else {
        continue
      }
      normalized.append(candidate)
    }

    return normalized
  }
}
