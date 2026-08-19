import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

let conversionPlannerTests: [TestCase] = [
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
