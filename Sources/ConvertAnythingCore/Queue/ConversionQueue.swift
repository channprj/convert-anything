import Foundation

public enum ConversionJobState: Equatable, Sendable {
  case queued
  case probing
  case converting(progress: Double)
  case validating
  case succeeded(output: URL, outputByteCount: Int64)
  case failed(ConversionFailure)
  case canceled

  public var isTerminal: Bool {
    switch self {
    case .succeeded, .failed, .canceled:
      true
    case .queued, .probing, .converting, .validating:
      false
    }
  }
}

public struct ConversionJob: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let plan: ConversionPlan
  public var state: ConversionJobState

  public init(id: UUID, plan: ConversionPlan, state: ConversionJobState) {
    self.id = id
    self.plan = plan
    self.state = state
  }
}

public struct QueueSnapshot: Equatable, Sendable {
  public let jobs: [ConversionJob]
  public let unfinishedCount: Int
  public let isRunning: Bool

  public init(jobs: [ConversionJob], unfinishedCount: Int, isRunning: Bool) {
    self.jobs = jobs
    self.unfinishedCount = unfinishedCount
    self.isRunning = isRunning
  }
}

public enum QueueError: Error, Equatable, Sendable {
  case failedJobNotFound(UUID)
  case retryRequiresFailedJob(UUID)
  case duplicateJobID(UUID)
}

public protocol QueueServing: Sendable {
  func enqueue(_ plans: [ConversionPlan]) async
  func cancel(jobID: UUID) async
  func retry(failedJobID: UUID, with plan: ConversionPlan) async throws
  func remove(jobID: UUID) async
  func clearFinished() async
  func snapshots() async -> AsyncStream<QueueSnapshot>
  func drainEvents() async -> AsyncStream<DrainSummary>
}

public actor ConversionQueue: QueueServing {
  private let converter: any ConversionServicing
  private let clock = ContinuousClock()

  private var jobs: [ConversionJob] = []
  private var queuedJobIDs: [UUID] = []
  private var activeJobID: UUID?
  private var drainTask: Task<Void, Never>?
  private var lastProgressUpdate: [UUID: ContinuousClock.Instant] = [:]
  private var accumulator = DrainAccumulator()
  private var snapshotContinuations: [UUID: AsyncStream<QueueSnapshot>.Continuation] = [:]
  private var drainContinuations: [UUID: AsyncStream<DrainSummary>.Continuation] = [:]

  public init(converter: any ConversionServicing) {
    self.converter = converter
  }

  public func enqueue(_ plans: [ConversionPlan]) async {
    let knownIDs = Set(jobs.map(\.id))
    var acceptedIDs = Set<UUID>()
    for plan in plans
    where !knownIDs.contains(plan.id) && acceptedIDs.insert(plan.id).inserted {
      jobs.append(ConversionJob(id: plan.id, plan: plan, state: .queued))
      queuedJobIDs.append(plan.id)
    }
    guard !acceptedIDs.isEmpty else { return }

    publishSnapshot()
    startDrainIfNeeded()
  }

  public func cancel(jobID: UUID) async {
    guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
    switch jobs[index].state {
    case .queued:
      queuedJobIDs.removeAll { $0 == jobID }
      jobs[index].state = .canceled
      accumulator.recordCanceled()
      publishSnapshot()
    case .probing, .converting, .validating:
      await converter.cancel(jobID: jobID)
    case .succeeded, .failed, .canceled:
      return
    }
  }

  public func retry(failedJobID: UUID, with plan: ConversionPlan) async throws {
    guard let failedJob = jobs.first(where: { $0.id == failedJobID }) else {
      throw QueueError.failedJobNotFound(failedJobID)
    }
    guard case .failed = failedJob.state else {
      throw QueueError.retryRequiresFailedJob(failedJobID)
    }
    guard !jobs.contains(where: { $0.id == plan.id }) else {
      throw QueueError.duplicateJobID(plan.id)
    }
    await enqueue([plan])
  }

  public func remove(jobID: UUID) async {
    guard let index = jobs.firstIndex(where: { $0.id == jobID }),
      jobs[index].state.isTerminal
    else {
      return
    }
    jobs.remove(at: index)
    publishSnapshot()
  }

  public func clearFinished() async {
    let remaining = jobs.filter { !$0.state.isTerminal }
    guard remaining.count != jobs.count else { return }
    jobs = remaining
    publishSnapshot()
  }

  public func snapshots() async -> AsyncStream<QueueSnapshot> {
    let subscriptionID = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      snapshotContinuations[subscriptionID] = continuation
      continuation.yield(snapshot())
      continuation.onTermination = { @Sendable _ in
        Task { await self.removeSnapshotContinuation(subscriptionID) }
      }
    }
  }

  public func drainEvents() async -> AsyncStream<DrainSummary> {
    let subscriptionID = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      drainContinuations[subscriptionID] = continuation
      continuation.onTermination = { @Sendable _ in
        Task { await self.removeDrainContinuation(subscriptionID) }
      }
    }
  }

  private func startDrainIfNeeded() {
    guard drainTask == nil, !queuedJobIDs.isEmpty else { return }
    drainTask = Task { await self.runDrain() }
  }

  private func runDrain() async {
    while let jobID = nextQueuedJobID(),
      let index = jobs.firstIndex(where: { $0.id == jobID })
    {
      activeJobID = jobID
      jobs[index].state = .probing
      publishSnapshot()
      let plan = jobs[index].plan
      let outcome = await converter.convert(plan) { [weak self] value in
        guard let self else { return }
        Task { await self.recordProgress(value, for: jobID) }
      }
      finish(jobID: jobID, plan: plan, outcome: outcome)
    }
    finishDrain()
  }

  private func nextQueuedJobID() -> UUID? {
    while !queuedJobIDs.isEmpty {
      let jobID = queuedJobIDs.removeFirst()
      if let job = jobs.first(where: { $0.id == jobID }), job.state == .queued {
        return jobID
      }
    }
    return nil
  }

  private func recordProgress(_ rawValue: Double, for jobID: UUID) {
    guard activeJobID == jobID,
      let index = jobs.firstIndex(where: { $0.id == jobID }),
      !jobs[index].state.isTerminal
    else {
      return
    }

    let value = min(1, max(0, rawValue.isFinite ? rawValue : 0))
    let now = clock.now
    if value < 1, let lastUpdate = lastProgressUpdate[jobID],
      lastUpdate.duration(to: now) < .milliseconds(100)
    {
      return
    }
    lastProgressUpdate[jobID] = now
    jobs[index].state = value == 1 ? .validating : .converting(progress: value)
    publishSnapshot()
  }

  private func finish(jobID: UUID, plan: ConversionPlan, outcome: ConversionOutcome) {
    guard let index = jobs.firstIndex(where: { $0.id == jobID }),
      !jobs[index].state.isTerminal
    else {
      return
    }

    switch outcome {
    case .succeeded(let output, let outputByteCount):
      jobs[index].state = .succeeded(output: output, outputByteCount: outputByteCount)
      accumulator.recordSuccess(
        sourceByteCount: plan.sourceByteCount,
        outputByteCount: outputByteCount,
        output: output
      )
    case .failed(let failure):
      jobs[index].state = .failed(failure)
      accumulator.recordFailure()
    case .canceled:
      jobs[index].state = .canceled
      accumulator.recordCanceled()
    }
    activeJobID = nil
    lastProgressUpdate.removeValue(forKey: jobID)
    publishSnapshot()
  }

  private func finishDrain() {
    drainTask = nil
    let summary = accumulator.summary
    accumulator = DrainAccumulator()
    for continuation in drainContinuations.values {
      continuation.yield(summary)
    }
  }

  private func snapshot() -> QueueSnapshot {
    let unfinishedCount = jobs.count { !$0.state.isTerminal }
    return QueueSnapshot(
      jobs: jobs,
      unfinishedCount: unfinishedCount,
      isRunning: unfinishedCount > 0
    )
  }

  private func publishSnapshot() {
    let value = snapshot()
    for continuation in snapshotContinuations.values {
      continuation.yield(value)
    }
  }

  private func removeSnapshotContinuation(_ subscriptionID: UUID) {
    snapshotContinuations.removeValue(forKey: subscriptionID)
  }

  private func removeDrainContinuation(_ subscriptionID: UUID) {
    drainContinuations.removeValue(forKey: subscriptionID)
  }
}

private struct DrainAccumulator {
  private(set) var succeededCount = 0
  private(set) var failedCount = 0
  private(set) var canceledCount = 0
  private(set) var bytesSaved: Int64 = 0
  private(set) var lastSuccessfulOutput: URL?

  var summary: DrainSummary {
    DrainSummary(
      succeededCount: succeededCount,
      failedCount: failedCount,
      canceledCount: canceledCount,
      bytesSaved: bytesSaved,
      lastSuccessfulOutput: lastSuccessfulOutput
    )
  }

  mutating func recordSuccess(
    sourceByteCount: Int64,
    outputByteCount: Int64,
    output: URL
  ) {
    succeededCount += 1
    let source = max(0, sourceByteCount)
    let encoded = max(0, outputByteCount)
    let saved = source > encoded ? source - encoded : 0
    let (total, overflow) = bytesSaved.addingReportingOverflow(saved)
    bytesSaved = overflow ? Int64.max : total
    lastSuccessfulOutput = output
  }

  mutating func recordFailure() {
    failedCount += 1
  }

  mutating func recordCanceled() {
    canceledCount += 1
  }
}
