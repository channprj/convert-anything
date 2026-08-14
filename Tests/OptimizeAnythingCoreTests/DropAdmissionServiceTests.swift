import Foundation
import OptimizeAnythingCore

let dropAdmissionServiceTests: [TestCase] = [
  TestCase("admission returns per-path results without aborting mixed batch") {
    let wav = try fixtureFile(named: "VOICE.WAV")
    defer { try? FileManager.default.removeItem(at: wav.deletingLastPathComponent()) }
    let text = wav.deletingLastPathComponent().appendingPathComponent("notes.txt")
    try Data([2]).write(to: text)

    let decisions = await DropAdmissionService().admit(
      [wav, text], rules: RuleCatalog.defaultRules)

    try expectEqual(
      decisions.map(\.status),
      [
        .accepted(ruleID: RuleCatalog.audioRuleID),
        .rejected(.unsupportedExtension("txt")),
      ]
    )
  },
  TestCase("admission rejects missing paths directories and extensionless files independently") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let missing = directory.appendingPathComponent("missing.wav")
    let extensionless = directory.appendingPathComponent("README")
    try Data([1]).write(to: extensionless)

    let decisions = await DropAdmissionService().admit(
      [missing, directory, extensionless],
      rules: RuleCatalog.defaultRules
    )

    try expectEqual(
      decisions.map(\.status),
      [
        .rejected(.missingFile),
        .rejected(.notRegularFile),
        .rejected(.missingExtension),
      ]
    )
  },
  TestCase("admission resolves a symlink before accepting its target") {
    let target = try fixtureFile(named: "voice.wav")
    defer { try? FileManager.default.removeItem(at: target.deletingLastPathComponent()) }
    let link = target.deletingLastPathComponent().appendingPathComponent("shortcut.wav")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let decision = try await firstDecision(for: link)

    try expectEqual(decision.input, target.resolvingSymlinksInPath())
    try expectEqual(decision.status, .accepted(ruleID: RuleCatalog.audioRuleID))
  },
  TestCase("admission rejects an unreadable regular file") {
    let file = try fixtureFile(named: "locked.wav")
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)

    let decision = try await firstDecision(for: file)

    try expectEqual(decision.status, .rejected(.unreadableFile))
  },
  TestCase("planner records allocated size and resolves a sibling output") {
    let input = try fixtureFile(named: "voice.wav", bytes: Data(repeating: 7, count: 4_096))
    defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
    let jobID = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
    let planner = ConversionPlanner(availableCapacity: { _ in Int64.max })

    let plan = try await planner.plan(
      input: input,
      rule: RuleCatalog.defaultRules[0],
      jobID: jobID
    )

    try expectEqual(plan.id, jobID)
    try expectEqual(plan.input, input)
    try expectTrue(plan.sourceByteCount >= 4_096)
    try expectEqual(
      plan.output.final.deletingLastPathComponent(), input.deletingLastPathComponent())
  },
  TestCase("planner fails before conversion when conservative capacity cannot fit") {
    let input = try fixtureFile(named: "voice.wav", bytes: Data(repeating: 7, count: 4_096))
    defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
    let planner = ConversionPlanner(availableCapacity: { _ in 1 })

    do {
      _ = try await planner.plan(
        input: input,
        rule: RuleCatalog.defaultRules[0],
        jobID: UUID()
      )
      throw TestFailure(description: "Expected insufficient disk space")
    } catch let error as PlanningError {
      guard case .insufficientDiskSpace(let required, let available) = error else {
        throw TestFailure(description: "Unexpected planning error: \(error)")
      }
      try expectTrue(required > 64 * 1_024 * 1_024)
      try expectEqual(available, 1)
    }
  },
]

private func firstDecision(for url: URL) async throws -> AdmissionDecision {
  let decisions = await DropAdmissionService().admit([url], rules: RuleCatalog.defaultRules)
  guard let decision = decisions.first else {
    throw TestFailure(description: "Expected one admission decision")
  }
  return decision
}
