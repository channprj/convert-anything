import AppKit
import ConvertAnythingCore
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation
import SwiftUI

let popoverViewTests: [TestCase] = [
  TestCase("empty popover keeps its footer on the bottom edge") {
    try await emptyPopoverFillsFixedHeight()
  },
  TestCase("targeted popover highlights the full drop area without hiding controls") {
    try await targetedPopoverKeepsControlsVisible()
  },
]

/// The popover is shown at a fixed content size, so the empty drop prompt has
/// to stretch vertically. When it only claims its ideal height the whole stack
/// centers itself and the header and footer drift inward, which does not match
/// the job list layout.
@MainActor
private func emptyPopoverFillsFixedHeight() throws {
  _ = NSApplication.shared
  let size = NSSize(width: 360, height: 430)
  let model = makeModel()
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
private func targetedPopoverKeepsControlsVisible() throws {
  _ = NSApplication.shared
  let size = NSSize(width: 360, height: 430)
  let model = makeModel()
  let presentation = DropPresentationCoordinator(exitGracePeriod: .seconds(1))
  presentation.setTargeted(true, at: .popover)
  let host = NSHostingView(
    rootView: PopoverView(
      model: model,
      dropPresentation: presentation,
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

  let idlePresentation = DropPresentationCoordinator(exitGracePeriod: .seconds(1))
  let idleHost = NSHostingView(
    rootView: PopoverView(
      model: model,
      dropPresentation: idlePresentation,
      onSettings: {},
      onQuit: {}
    )
  )
  idleHost.frame = NSRect(origin: .zero, size: size)
  let idleWindow = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  idleWindow.contentView = idleHost
  idleHost.layoutSubtreeIfNeeded()

  let activePixels = try renderedBytes(of: host)
  let idlePixels = try renderedBytes(of: idleHost)
  let differingBytes = zip(activePixels, idlePixels).reduce(into: 0) { count, pair in
    if pair.0 != pair.1 { count += 1 }
  }
  let activeButtonCount = descendants(of: host).compactMap { $0 as? NSButton }.count
  let idleButtonCount = descendants(of: idleHost).compactMap { $0 as? NSButton }.count
  try expectEqual(PopoverView.dropTargetLabel, "Drop to convert")
  try expectTrue(
    differingBytes > 1_000,
    "Targeted and idle popovers differed by only \(differingBytes) rendered bytes"
  )
  try expectTrue(activeButtonCount >= 2, "Targeted popover rendered no footer controls")
  try expectEqual(activeButtonCount, idleButtonCount, "Targeting changed footer control count")
}

@MainActor
private func makeModel() -> AppViewModel {
  AppViewModel(
    dependencies: ViewModelDependencies(
      settings: FakeSettingsStore(),
      admission: FakeAdmissionService(),
      planner: FakePlanner(),
      queue: FakeQueue(),
      notifications: FakeNotificationService(),
      finder: FakeFinderService()
    )
  )
}

@MainActor
private func descendants(of view: NSView) -> [NSView] {
  view.subviews.flatMap { [$0] + descendants(of: $0) }
}

@MainActor
private func renderedBytes(of view: NSView) throws -> Data {
  view.needsDisplay = true
  view.displayIfNeeded()
  guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    throw TestFailure(description: "Popover did not create a bitmap representation")
  }
  view.cacheDisplay(in: view.bounds, to: bitmap)
  guard let bytes = bitmap.bitmapData else {
    throw TestFailure(description: "Popover bitmap has no pixel data")
  }
  return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
}
