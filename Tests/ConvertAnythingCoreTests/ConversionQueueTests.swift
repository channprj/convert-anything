import ConvertAnythingCore
import Foundation

let conversionQueueTests: [TestCase] = [
  TestCase("queue runs exactly one conversion at a time") {
    let plans = try makeQueuePlans(byteCounts: [100, 80])
    defer { removeQueuePlanDirectories(plans) }
    let converter = ControlledConverter()
    let queue = ConversionQueue(converter: converter)

    await queue.enqueue(plans)
    try await converter.waitUntilStarted(plans[0].id)
    let firstStartedIDs = await converter.started()
    try expectEqual(firstStartedIDs, [plans[0].id])

    await converter.finish(
      plans[0].id,
      with: .succeeded(output: plans[0].output.final, outputByteCount: 40)
    )
    try await converter.waitUntilStarted(plans[1].id)
    let allStartedIDs = await converter.started()
    try expectEqual(allStartedIDs, [plans[0].id, plans[1].id])
    await converter.finish(plans[1].id, with: .canceled)
  },
  TestCase("drops during active work share one drain summary") {
    let plans = try makeQueuePlans(byteCounts: [100, 80])
    defer { removeQueuePlanDirectories(plans) }
    let converter = ControlledConverter()
    let queue = ConversionQueue(converter: converter)
    let drainStream = await queue.drainEvents()

    await queue.enqueue([plans[0]])
    try await converter.waitUntilStarted(plans[0].id)
    await queue.enqueue([plans[1]])
    await converter.finish(
      plans[0].id,
      with: .succeeded(output: plans[0].output.final, outputByteCount: 40)
    )
    try await converter.waitUntilStarted(plans[1].id)
    await converter.finish(
      plans[1].id,
      with: .succeeded(output: plans[1].output.final, outputByteCount: 30)
    )

    let summary = try await firstValue(from: drainStream)
    try expectEqual(summary.succeededCount, 2)
    try expectEqual(summary.failedCount, 0)
    try expectEqual(summary.bytesSaved, 110)
    try expectEqual(summary.lastSuccessfulOutput, plans[1].output.final)
  },
  TestCase("canceling active work forwards cancellation and continues queue") {
    let plans = try makeQueuePlans(byteCounts: [10, 10])
    defer { removeQueuePlanDirectories(plans) }
    let converter = ControlledConverter(cancelFinishesConversion: true)
    let queue = ConversionQueue(converter: converter)

    await queue.enqueue(plans)
    try await converter.waitUntilStarted(plans[0].id)
    await queue.cancel(jobID: plans[0].id)
    try await converter.waitUntilStarted(plans[1].id)

    let canceledIDs = await converter.canceled()
    let startedIDs = await converter.started()
    try expectEqual(canceledIDs, [plans[0].id])
    try expectEqual(startedIDs, [plans[0].id, plans[1].id])
    await converter.finish(plans[1].id, with: .canceled)
  },
  TestCase("canceling queued work never starts it and counts it once") {
    let plans = try makeQueuePlans(byteCounts: [10, 10])
    defer { removeQueuePlanDirectories(plans) }
    let converter = ControlledConverter()
    let queue = ConversionQueue(converter: converter)
    let drainStream = await queue.drainEvents()

    await queue.enqueue(plans)
    try await converter.waitUntilStarted(plans[0].id)
    await queue.cancel(jobID: plans[1].id)
    await converter.finish(plans[0].id, with: .canceled)

    let summary = try await firstValue(from: drainStream)
    let startedIDs = await converter.started()
    try expectEqual(startedIDs, [plans[0].id])
    try expectEqual(summary.canceledCount, 2)
  },
  TestCase("retry preserves failed job and enqueues a new plan ID") {
    let plans = try makeQueuePlans(byteCounts: [10, 10])
    defer { removeQueuePlanDirectories(plans) }
    let converter = ControlledConverter()
    let queue = ConversionQueue(converter: converter)
    let failure = ConversionFailure(category: .encoderFailed, message: "boom")

    await queue.enqueue([plans[0]])
    try await converter.waitUntilStarted(plans[0].id)
    await converter.finish(plans[0].id, with: .failed(failure))
    try await eventually {
      let snapshot = await queue.snapshots()
      guard let first = try? await firstValue(from: snapshot, timeout: .milliseconds(100)) else {
        return false
      }
      return first.jobs.first?.state == .failed(failure)
    }

    try await queue.retry(failedJobID: plans[0].id, with: plans[1])
    try await converter.waitUntilStarted(plans[1].id)
    let snapshot = try await firstValue(from: await queue.snapshots())

    try expectEqual(snapshot.jobs.count, 2)
    try expectEqual(snapshot.jobs[0].state, .failed(failure))
    try expectTrue(
      snapshot.jobs[1].state == .probing || snapshot.jobs[1].state == .converting(progress: 0))
    await converter.finish(plans[1].id, with: .canceled)
  },
]

private actor ControlledConverter: ConversionServicing {
  private let cancelFinishesConversion: Bool
  private var startedIDs: [UUID] = []
  private var canceledIDs: [UUID] = []
  private var continuations: [UUID: CheckedContinuation<ConversionOutcome, Never>] = [:]

  init(cancelFinishesConversion: Bool = false) {
    self.cancelFinishesConversion = cancelFinishesConversion
  }

  func convert(
    _ plan: ConversionPlan,
    progress: @escaping @Sendable (Double) -> Void
  ) async -> ConversionOutcome {
    startedIDs.append(plan.id)
    progress(0)
    return await withCheckedContinuation { continuations[plan.id] = $0 }
  }

  func cancel(jobID: UUID) async {
    canceledIDs.append(jobID)
    if cancelFinishesConversion {
      finish(jobID, with: .canceled)
    }
  }

  func waitUntilStarted(_ jobID: UUID) async throws {
    try await eventually { await self.startedIDs.contains(jobID) }
  }

  func finish(_ jobID: UUID, with outcome: ConversionOutcome) {
    continuations.removeValue(forKey: jobID)?.resume(returning: outcome)
  }

  func started() -> [UUID] {
    startedIDs
  }

  func canceled() -> [UUID] {
    canceledIDs
  }
}

private func makeQueuePlans(byteCounts: [Int]) throws -> [ConversionPlan] {
  try byteCounts.enumerated().map { index, byteCount in
    let input = try fixtureFile(
      named: "queue-\(index).wav",
      bytes: Data(repeating: UInt8(index + 1), count: byteCount)
    )
    let base = try makePlan(for: input, target: .m4a)
    let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 101))!
    let output = try OutputPathResolver().resolve(input: input, target: .m4a, jobID: id)
    return ConversionPlan(
      id: id,
      input: input,
      output: output,
      rule: base.rule,
      sourceByteCount: Int64(byteCount)
    )
  }
}

private func removeQueuePlanDirectories(_ plans: [ConversionPlan]) {
  for plan in plans {
    try? FileManager.default.removeItem(at: plan.input.deletingLastPathComponent())
  }
}
