import Combine
import ConvertAnythingCore
import Foundation

public enum NotificationAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
}

public protocol NotificationServing: Sendable {
  func authorizationStatus() async -> NotificationAuthorizationStatus
  func requestAuthorizationIfNeeded() async
  func deliver(_ summary: DrainSummary) async throws
}

public protocol FinderServing: Sendable {
  @MainActor func reveal(_ url: URL)
}

public struct ViewModelDependencies: Sendable {
  public let settings: any SettingsServing
  public let admission: any DropAdmitting
  public let planner: any ConversionPlanning
  public let queue: any QueueServing
  public let notifications: any NotificationServing
  public let finder: any FinderServing

  public init(
    settings: any SettingsServing,
    admission: any DropAdmitting,
    planner: any ConversionPlanning,
    queue: any QueueServing,
    notifications: any NotificationServing,
    finder: any FinderServing
  ) {
    self.settings = settings
    self.admission = admission
    self.planner = planner
    self.queue = queue
    self.notifications = notifications
    self.finder = finder
  }
}

@MainActor
public final class AppViewModel: ObservableObject {
  @Published public private(set) var rules: [ConversionRule] = RuleCatalog.defaultRules
  @Published public private(set) var snapshot = QueueSnapshot(jobs: [])
  @Published public private(set) var admissionErrors: [String] = []
  @Published public private(set) var lastDrainSummary: DrainSummary?
  @Published public private(set) var settingsError: String?
  @Published public private(set) var toolsAvailable: Bool

  private let dependencies: ViewModelDependencies
  private var settingsLoaded = false
  private var notificationAuthorizationRequested = false
  private var snapshotTask: Task<Void, Never>?
  private var drainTask: Task<Void, Never>?

  public init(dependencies: ViewModelDependencies, toolsAvailable: Bool = true) {
    self.dependencies = dependencies
    self.toolsAvailable = toolsAvailable
    observeQueue()
  }

  deinit {
    snapshotTask?.cancel()
    drainTask?.cancel()
  }

  public func handleDrop(_ urls: [URL]) async {
    guard !urls.isEmpty else { return }
    await loadSettingsIfNeeded()
    let decisions = await dependencies.admission.admit(urls, rules: rules)
    let accepted = decisions.filter {
      if case .accepted = $0.status { return true }
      return false
    }
    admissionErrors = decisions.compactMap { decision in
      guard case .rejected(let error) = decision.status else { return nil }
      return "\(decision.input.lastPathComponent): \(Self.admissionMessage(error))"
    }
    guard !accepted.isEmpty else { return }
    guard toolsAvailable else {
      admissionErrors.append("Bundled FFmpeg tools are unavailable")
      return
    }

    if !notificationAuthorizationRequested {
      notificationAuthorizationRequested = true
      await dependencies.notifications.requestAuthorizationIfNeeded()
    }

    var plans: [ConversionPlan] = []
    for decision in accepted {
      guard case .accepted(let ruleID) = decision.status,
        let rule = rules.first(where: { $0.id == ruleID })
      else {
        continue
      }
      do {
        plans.append(
          try await dependencies.planner.plan(
            input: decision.input,
            rule: rule,
            jobID: UUID()
          )
        )
      } catch {
        admissionErrors.append("\(decision.input.lastPathComponent): \(error.localizedDescription)")
      }
    }
    if !plans.isEmpty {
      await dependencies.queue.enqueue(plans)
    }
  }

  public func loadSettings() async {
    await loadSettingsIfNeeded()
  }

  public func receiveDrain(_ summary: DrainSummary) async {
    lastDrainSummary = summary
    guard await dependencies.notifications.authorizationStatus() == .authorized else { return }
    try? await dependencies.notifications.deliver(summary)
  }

  public func cancel(jobID: UUID) async {
    await dependencies.queue.cancel(jobID: jobID)
  }

  public func retry(job: ConversionJob) async {
    guard case .failed = job.state else { return }
    do {
      let plan = try await dependencies.planner.plan(
        input: job.plan.input,
        rule: job.plan.rule,
        jobID: UUID()
      )
      try await dependencies.queue.retry(failedJobID: job.id, with: plan)
    } catch {
      admissionErrors.append("\(job.plan.input.lastPathComponent): \(error.localizedDescription)")
    }
  }

  public func remove(jobID: UUID) async {
    await dependencies.queue.remove(jobID: jobID)
  }

  public func clearFinishedJobs() async {
    await dependencies.queue.clearFinished()
  }

  public func reveal(_ url: URL) {
    dependencies.finder.reveal(url)
  }

  public func saveRules(_ proposedRules: [ConversionRule]) async {
    do {
      let validated = try RuleValidator.validate(proposedRules)
      let document = SettingsDocument(rules: validated)
      try await dependencies.settings.save(document)
      rules = validated
      settingsError = nil
    } catch {
      settingsError = Self.settingsMessage(error)
      if let document = try? await dependencies.settings.load() {
        rules = document.rules
      }
    }
  }

  public func restoreDefaultRules() async {
    await saveRules(RuleCatalog.defaultRules)
  }

  private func loadSettingsIfNeeded() async {
    guard !settingsLoaded else { return }
    settingsLoaded = true
    do {
      let document = try await dependencies.settings.load()
      rules = document.rules
      settingsError = nil
    } catch {
      settingsError = Self.settingsMessage(error)
    }
  }

  private func observeQueue() {
    let queue = dependencies.queue
    snapshotTask = Task { [weak self] in
      let stream = await queue.snapshots()
      for await value in stream {
        guard !Task.isCancelled else { return }
        self?.snapshot = value
      }
    }
    drainTask = Task { [weak self] in
      let stream = await queue.drainEvents()
      for await value in stream {
        guard !Task.isCancelled else { return }
        await self?.receiveDrain(value)
      }
    }
  }

  private static func admissionMessage(_ error: AdmissionError) -> String {
    switch error {
    case .missingFile: "File not found"
    case .notRegularFile: "Only files can be converted"
    case .unreadableFile: "File is not readable"
    case .missingExtension: "File has no extension"
    case .unsupportedExtension(let value): "Unsupported .\(value) file"
    }
  }

  private static func settingsMessage(_ error: any Error) -> String {
    switch error {
    case RuleValidationError.emptySourceExtensions:
      "Every rule needs at least one source extension"
    case RuleValidationError.incompatibleTarget:
      "The selected target does not match the media family"
    case RuleValidationError.duplicateSourceExtension(let value):
      "The .\(value) extension is already handled by another enabled rule"
    case RuleValidationError.unsupportedSchemaVersion:
      "These settings were created by an unsupported app version"
    default:
      error.localizedDescription
    }
  }
}
