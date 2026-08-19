import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

let drainSummaryTests: [TestCase] = [
  TestCase("drain summary is an immutable sendable value") {
    let output = URL(fileURLWithPath: "/tmp/output.m4a")
    let summary = DrainSummary(
      succeededCount: 2,
      failedCount: 1,
      canceledCount: 3,
      bytesSaved: 42,
      lastSuccessfulOutput: output
    )

    try expectEqual(summary.succeededCount, 2)
    try expectEqual(summary.failedCount, 1)
    try expectEqual(summary.canceledCount, 3)
    try expectEqual(summary.bytesSaved, 42)
    try expectEqual(summary.lastSuccessfulOutput, output)
  },
  TestCase("queue never reports negative byte savings") {
    let plans = try makeDrainPlans()
    defer {
      for plan in plans {
        try? FileManager.default.removeItem(at: plan.input.deletingLastPathComponent())
      }
    }
    let converter = ImmediateConverter(outcomes: [
      .succeeded(output: plans[0].output.final, outputByteCount: 40),
      .succeeded(output: plans[1].output.final, outputByteCount: 50),
    ])
    let queue = ConversionQueue(converter: converter)
    let stream = await queue.drainEvents()

    await queue.enqueue(plans)
    let summary = try await firstValue(from: stream)

    try expectEqual(summary.bytesSaved, 60)
  },
]

private actor ImmediateConverter: ConversionServicing {
  private var outcomes: [ConversionOutcome]

  init(outcomes: [ConversionOutcome]) {
    self.outcomes = outcomes
  }

  func convert(
    _ plan: ConversionPlan,
    progress: @escaping @Sendable (Double) -> Void
  ) async -> ConversionOutcome {
    progress(1)
    return outcomes.removeFirst()
  }

  func cancel(jobID: UUID) async {}
}

private func makeDrainPlans() throws -> [ConversionPlan] {
  var plans: [ConversionPlan] = []
  for (index, byteCount) in [100, 10].enumerated() {
    let input = try fixtureFile(
      named: "summary-\(index).wav",
      bytes: Data(repeating: 1, count: byteCount)
    )
    let base = try makePlan(for: input, target: .m4a)
    plans.append(
      ConversionPlan(
        id: UUID(),
        input: base.input,
        output: base.output,
        rule: base.rule,
        sourceByteCount: Int64(byteCount)
      )
    )
  }
  return plans
}
