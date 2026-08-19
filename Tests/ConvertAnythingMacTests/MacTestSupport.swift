import ConvertAnythingCore
import ConvertAnythingMac
import Foundation

struct MacTestCase: Sendable {
  let name: String
  let body: @Sendable () async throws -> Void

  init(_ name: String, body: @escaping @Sendable () async throws -> Void) {
    self.name = name
    self.body = body
  }
}

struct MacTestFailure: Error, CustomStringConvertible {
  let description: String
}

func macExpectTrue(
  _ value: @autoclosure () throws -> Bool,
  _ message: @autoclosure () -> String = "Expected condition to be true"
) throws {
  guard try value() else { throw MacTestFailure(description: message()) }
}

func macExpectEqual<T: Equatable>(
  _ actual: @autoclosure () throws -> T,
  _ expected: @autoclosure () throws -> T
) throws {
  let actualValue = try actual()
  let expectedValue = try expected()
  guard actualValue == expectedValue else {
    throw MacTestFailure(
      description:
        "Expected \(String(describing: expectedValue)), got \(String(describing: actualValue))"
    )
  }
}

actor FakeSettingsStore: SettingsServing {
  private var document: SettingsDocument
  private(set) var savedDocuments: [SettingsDocument] = []

  init(document: SettingsDocument = SettingsDocument(rules: RuleCatalog.defaultRules)) {
    self.document = document
  }

  func load() async throws -> SettingsDocument {
    document
  }

  func save(_ document: SettingsDocument) async throws {
    self.document = document
    savedDocuments.append(document)
  }
}

actor FakeAdmissionService: DropAdmitting {
  func admit(_ urls: [URL], rules: [ConversionRule]) async -> [AdmissionDecision] {
    urls.map { url in
      let sourceExtension = url.pathExtension.lowercased()
      if let rule = rules.first(where: {
        $0.isEnabled && $0.sourceExtensions.contains(sourceExtension)
      }) {
        return AdmissionDecision(input: url, status: .accepted(ruleID: rule.id))
      }
      return AdmissionDecision(
        input: url, status: .rejected(.unsupportedExtension(sourceExtension)))
    }
  }
}

actor FakePlanner: ConversionPlanning {
  private(set) var inputs: [URL] = []

  func plan(input: URL, rule: ConversionRule, jobID: UUID) async throws -> ConversionPlan {
    inputs.append(input)
    let directory = input.deletingLastPathComponent()
    let stem = input.deletingPathExtension().lastPathComponent
    let output = OutputPaths(
      final: directory.appendingPathComponent("\(stem).\(rule.target.rawValue)"),
      temporary: directory.appendingPathComponent(".\(stem)-\(jobID).tmp")
    )
    return ConversionPlan(
      id: jobID,
      input: input,
      output: output,
      rule: rule,
      sourceByteCount: 1
    )
  }
}

actor FakeQueue: QueueServing {
  private(set) var enqueuedPlans: [ConversionPlan] = []
  private(set) var canceledIDs: [UUID] = []
  private(set) var retries: [(UUID, ConversionPlan)] = []
  private(set) var removedIDs: [UUID] = []
  private(set) var clearRequestCount = 0

  func enqueue(_ plans: [ConversionPlan]) async {
    enqueuedPlans.append(contentsOf: plans)
  }

  func cancel(jobID: UUID) async {
    canceledIDs.append(jobID)
  }

  func retry(failedJobID: UUID, with plan: ConversionPlan) async throws {
    retries.append((failedJobID, plan))
  }

  func remove(jobID: UUID) async {
    removedIDs.append(jobID)
  }

  func clearFinished() async {
    clearRequestCount += 1
  }

  func snapshots() async -> AsyncStream<QueueSnapshot> {
    AsyncStream { continuation in
      continuation.yield(QueueSnapshot(jobs: []))
    }
  }

  func drainEvents() async -> AsyncStream<DrainSummary> {
    AsyncStream { _ in }
  }

  func enqueued() -> [ConversionPlan] {
    enqueuedPlans
  }
}

actor FakeNotificationService: NotificationServing {
  private let status: NotificationAuthorizationStatus
  private(set) var authorizationRequestCount = 0
  private(set) var delivered: [DrainSummary] = []

  init(status: NotificationAuthorizationStatus = .authorized) {
    self.status = status
  }

  func authorizationStatus() async -> NotificationAuthorizationStatus {
    status
  }

  func requestAuthorizationIfNeeded() async {
    authorizationRequestCount += 1
  }

  func deliver(_ summary: DrainSummary) async throws {
    delivered.append(summary)
  }

  func requestCount() -> Int {
    authorizationRequestCount
  }

  func deliveredSummaries() -> [DrainSummary] {
    delivered
  }
}

@MainActor
final class FakeFinderService: FinderServing, @unchecked Sendable {
  private(set) var revealed: [URL] = []

  func reveal(_ url: URL) {
    revealed.append(url)
  }
}
