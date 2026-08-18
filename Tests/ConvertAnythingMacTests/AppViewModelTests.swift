import ConvertAnythingCore
import ConvertAnythingMac
import Foundation

let appViewModelTests: [MacTestCase] = [
  MacTestCase("accepted drop requests notification once and enqueues plans") {
    try await acceptedDropRequestsNotificationOnce()
  },
  MacTestCase("denied notification keeps drain summary in popover") {
    try await deniedNotificationKeepsSummary()
  },
]

@MainActor
private func acceptedDropRequestsNotificationOnce() async throws {
  let settings = FakeSettingsStore()
  let admission = FakeAdmissionService()
  let planner = FakePlanner()
  let queue = FakeQueue()
  let notifications = FakeNotificationService()
  let finder = FakeFinderService()
  let model = AppViewModel(
    dependencies: ViewModelDependencies(
      settings: settings,
      admission: admission,
      planner: planner,
      queue: queue,
      notifications: notifications,
      finder: finder
    )
  )
  let wav = URL(fileURLWithPath: "/tmp/voice.wav")
  let mov = URL(fileURLWithPath: "/tmp/movie.mov")
  let png = URL(fileURLWithPath: "/tmp/overlay.png")

  await model.handleDrop([wav, mov])
  await model.handleDrop([png])

  let requestCount = await notifications.requestCount()
  let plans = await queue.enqueued()
  try macExpectEqual(requestCount, 1)
  try macExpectEqual(plans.map(\.input), [wav, mov, png])
}

@MainActor
private func deniedNotificationKeepsSummary() async throws {
  let notifications = FakeNotificationService(status: .denied)
  let model = AppViewModel(
    dependencies: ViewModelDependencies(
      settings: FakeSettingsStore(),
      admission: FakeAdmissionService(),
      planner: FakePlanner(),
      queue: FakeQueue(),
      notifications: notifications,
      finder: FakeFinderService()
    )
  )
  let summary = DrainSummary(
    succeededCount: 1,
    failedCount: 0,
    canceledCount: 0,
    bytesSaved: 42,
    lastSuccessfulOutput: URL(fileURLWithPath: "/tmp/output.m4a")
  )

  await model.receiveDrain(summary)

  let delivered = await notifications.deliveredSummaries()
  try macExpectEqual(model.lastDrainSummary, summary)
  try macExpectEqual(delivered, [])
}
