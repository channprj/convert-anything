import AppKit
import ConvertAnythingCore
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation
import SwiftUI

let popoverViewTests: [TestCase] = [
  TestCase("empty popover keeps its footer on the bottom edge") {
    try await emptyPopoverFillsFixedHeight()
  }
]

/// The popover is shown at a fixed content size, so the empty drop prompt has
/// to stretch vertically. When it only claims its ideal height the whole stack
/// centers itself and the header and footer drift inward, which does not match
/// the job list layout.
@MainActor
private func emptyPopoverFillsFixedHeight() throws {
  _ = NSApplication.shared
  let size = NSSize(width: 360, height: 430)
  let model = AppViewModel(
    dependencies: ViewModelDependencies(
      settings: FakeSettingsStore(),
      admission: FakeAdmissionService(),
      planner: FakePlanner(),
      queue: FakeQueue(),
      notifications: FakeNotificationService(),
      finder: FakeFinderService()
    )
  )
  try expectTrue(model.snapshot.jobs.isEmpty, "Popover must render its empty state")

  let host = NSHostingView(
    rootView: PopoverView(
      model: model,
      dropPresentation: DropPresentationCoordinator(),
      onSettings: {},
      onQuit: {}
    )
  )
  host.frame = NSRect(origin: .zero, size: size)
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  host.layoutSubtreeIfNeeded()

  // Only the footer buttons are real controls; the drop destination spans the
  // whole popover, so it cannot report where the stack ends.
  let footerButtons = descendants(of: host).compactMap { $0 as? NSButton }
  guard !footerButtons.isEmpty else {
    throw TestFailure(description: "Popover rendered no footer buttons to measure")
  }
  let footerBottom = footerButtons.map { $0.convert($0.bounds, to: host).maxY }.max() ?? 0
  let bottomGap = size.height - footerBottom

  try expectTrue(
    bottomGap <= 20,
    "Empty popover footer sits \(bottomGap)pt above the bottom edge, expected at most 20pt"
  )
}

@MainActor
private func descendants(of view: NSView) -> [NSView] {
  view.subviews.flatMap { [$0] + descendants(of: $0) }
}
