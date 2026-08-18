import Foundation

public protocol DropAdmitting: Sendable {
  func admit(_ urls: [URL], rules: [ConversionRule]) async -> [AdmissionDecision]
}

public struct DropAdmissionService: DropAdmitting {
  public init() {}

  public func admit(_ urls: [URL], rules: [ConversionRule]) async -> [AdmissionDecision] {
    let validatedRules = (try? RuleValidator.validate(rules)) ?? []

    return urls.map { originalURL in
      let input = originalURL.resolvingSymlinksInPath()
      let status = admissionStatus(for: input, rules: validatedRules)
      return AdmissionDecision(input: input, status: status)
    }
  }

  private func admissionStatus(for input: URL, rules: [ConversionRule]) -> AdmissionStatus {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
      return .rejected(.missingFile)
    }
    guard !isDirectory.boolValue,
      (try? input.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    else {
      return .rejected(.notRegularFile)
    }
    guard FileManager.default.isReadableFile(atPath: input.path) else {
      return .rejected(.unreadableFile)
    }

    let sourceExtension = input.pathExtension.lowercased()
    guard !sourceExtension.isEmpty else {
      return .rejected(.missingExtension)
    }
    guard
      let rule = rules.first(where: {
        $0.isEnabled && $0.sourceExtensions.contains(sourceExtension)
      })
    else {
      return .rejected(.unsupportedExtension(sourceExtension))
    }
    return .accepted(ruleID: rule.id)
  }
}
