import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation

let dropPresentationCoordinatorTests: [TestCase] = [
  TestCase("drop presentation bridges status item to popover") {
    try await presentationBridgesDestinations()
  },
  TestCase("drop presentation cancels after every destination exits") {
    try await presentationCancelsAfterGracePeriod()
  },
  TestCase("completed drop never reports cancellation") {
    try await completedDropDoesNotCancel()
  },
  TestCase("drag popover session closes only an auto-opened popover") {
    try await dragPopoverSessionPreservesManualPresentation()
  },
]

@MainActor
private func presentationBridgesDestinations() async throws {
  let coordinator = DropPresentationCoordinator(exitGracePeriod: .milliseconds(30))
  var activationCount = 0
  var cancellationCount = 0
  coordinator.onActivation = { activationCount += 1 }
  coordinator.onCancellation = { cancellationCount += 1 }

  coordinator.setTargeted(true, at: .statusItem)
  coordinator.setTargeted(false, at: .statusItem)
  try await Task.sleep(for: .milliseconds(10))
  coordinator.setTargeted(true, at: .popover)
  try await Task.sleep(for: .milliseconds(40))

  try expectTrue(coordinator.isActive)
  try expectEqual(activationCount, 1)
  try expectEqual(cancellationCount, 0)
}

@MainActor
private func presentationCancelsAfterGracePeriod() async throws {
  let coordinator = DropPresentationCoordinator(exitGracePeriod: .milliseconds(20))
  var cancellationCount = 0
  coordinator.onCancellation = { cancellationCount += 1 }

  coordinator.setTargeted(true, at: .statusItem)
  coordinator.setTargeted(true, at: .statusItem)
  coordinator.setTargeted(false, at: .statusItem)
  try await Task.sleep(for: .milliseconds(40))

  try expectTrue(!coordinator.isActive)
  try expectEqual(cancellationCount, 1)
}

@MainActor
private func completedDropDoesNotCancel() async throws {
  let coordinator = DropPresentationCoordinator(exitGracePeriod: .milliseconds(20))
  var completionCount = 0
  var cancellationCount = 0
  coordinator.onCompletion = { completionCount += 1 }
  coordinator.onCancellation = { cancellationCount += 1 }

  coordinator.setTargeted(true, at: .popover)
  coordinator.setTargeted(false, at: .popover)
  coordinator.completeDrop()
  try await Task.sleep(for: .milliseconds(40))

  try expectTrue(!coordinator.isActive)
  try expectEqual(completionCount, 1)
  try expectEqual(cancellationCount, 0)
}

@MainActor
private func dragPopoverSessionPreservesManualPresentation() throws {
  var autoOpened = DragPopoverSession()
  try expectTrue(autoOpened.begin(popoverIsShown: false))
  try expectTrue(autoOpened.cancel())

  var preOpened = DragPopoverSession()
  try expectTrue(!preOpened.begin(popoverIsShown: true))
  try expectTrue(!preOpened.cancel())

  var completed = DragPopoverSession()
  try expectTrue(completed.begin(popoverIsShown: false))
  completed.complete()
  try expectTrue(!completed.cancel())
}
