import AppKit
import ConvertAnythingCore
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation

let settingsWindowControllerTests: [TestCase] = [
  TestCase("settings window closes after a successful save") {
    try await settingsWindowClosesAfterSuccessfulSave()
  },
  TestCase("settings window stays open when saving fails") {
    try await settingsWindowStaysOpenAfterFailedSave()
  },
]

@MainActor
private func settingsWindowClosesAfterSuccessfulSave() async throws {
  let controller = SettingsWindowController(model: makeSettingsModel(settings: FakeSettingsStore()))
  controller.show()
  defer { controller.close() }

  try await clickSaveButton(in: controller)
  try await waitForSettingsCondition { controller.window?.isVisible == false }
}

@MainActor
private func settingsWindowStaysOpenAfterFailedSave() async throws {
  let model = makeSettingsModel(settings: FailingSettingsStore())
  let controller = SettingsWindowController(model: model)
  controller.show()
  defer { controller.close() }

  try await clickSaveButton(in: controller)
  try await waitForSettingsCondition { model.settingsError != nil }
  try expectTrue(controller.window?.isVisible == true)
}

@MainActor
private func clickSaveButton(in controller: SettingsWindowController) async throws {
  try await Task.sleep(for: .milliseconds(100))
  guard let window = controller.window,
    let returnKey = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "\r",
      charactersIgnoringModifiers: "\r",
      isARepeat: false,
      keyCode: 36
    )
  else {
    throw TestFailure(description: "Could not create the Settings Save shortcut event")
  }
  try expectTrue(
    window.performKeyEquivalent(with: returnKey),
    "Settings window did not handle the default Save shortcut"
  )
}

@MainActor
private func waitForSettingsCondition(
  timeout: Duration = .seconds(2),
  _ condition: @MainActor () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw TestFailure(description: "Settings condition was not met before timeout")
}

@MainActor
private func makeSettingsModel(settings: any SettingsServing) -> AppViewModel {
  AppViewModel(
    dependencies: ViewModelDependencies(
      settings: settings,
      admission: FakeAdmissionService(),
      planner: FakePlanner(),
      queue: FakeQueue(),
      notifications: FakeNotificationService(),
      finder: FakeFinderService()
    )
  )
}

private actor FailingSettingsStore: SettingsServing {
  func load() async throws -> SettingsDocument {
    SettingsDocument(rules: RuleCatalog.defaultRules)
  }

  func save(_ document: SettingsDocument) async throws {
    throw SaveFailure()
  }
}

private struct SaveFailure: LocalizedError {
  var errorDescription: String? { "Settings save failed" }
}
