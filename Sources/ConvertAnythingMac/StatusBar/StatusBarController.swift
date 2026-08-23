import AppKit
import Combine
import SwiftUI

public struct StatusItemTextPresentation: Equatable {
  public let length: CGFloat
  public let title: String

  public static func make(unfinishedCount: Int) -> Self {
    if unfinishedCount > 0 {
      return Self(length: NSStatusItem.variableLength, title: " \(unfinishedCount)")
    }
    return Self(length: NSStatusItem.squareLength, title: "")
  }
}

@MainActor
public final class StatusBarController {
  private let statusItem: NSStatusItem
  private let popover = NSPopover()
  private let model: AppViewModel
  private let dropView: StatusBarDropView
  private let dropPresentation: DropPresentationCoordinator
  private var cancellables = Set<AnyCancellable>()
  private var dragPopoverSession = DragPopoverSession()
  private var warningVisible = false

  public init(
    model: AppViewModel,
    onSettings: @escaping @MainActor () -> Void,
    onQuit: @escaping @MainActor () -> Void
  ) {
    self.model = model
    dropPresentation = DropPresentationCoordinator()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    dropView = StatusBarDropView(frame: .zero)

    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 430)
    popover.contentViewController = NSHostingController(
      rootView: PopoverView(
        model: model,
        dropPresentation: dropPresentation,
        onSettings: onSettings,
        onQuit: onQuit
      )
    )

    configureButton()
    configureDropPresentation()
    observeModel()
    updateButton()
  }

  private func configureButton() {
    guard let button = statusItem.button else { return }
    button.imagePosition = .imageLeading
    button.toolTip = "Convert Anything"
    dropView.frame = button.bounds
    dropView.autoresizingMask = [.width, .height]
    button.addSubview(dropView)

    dropView.onClick = { [weak self] in self?.togglePopover() }
    dropView.onTargetedChanged = { [weak self] active in
      self?.dropPresentation.setTargeted(active, at: .statusItem)
    }
    dropView.onDropURLs = { [weak self] urls in
      guard let self else { return }
      self.dropPresentation.completeDrop()
      Task { await self.model.handleDrop(urls) }
    }
  }

  private func configureDropPresentation() {
    dropPresentation.onActivation = { [weak self] in self?.beginDragPresentation() }
    dropPresentation.onCancellation = { [weak self] in self?.cancelDragPresentation() }
    dropPresentation.onCompletion = { [weak self] in self?.completeDragPresentation() }
  }

  private func observeModel() {
    model.$snapshot.sink { [weak self] _ in
      Task { @MainActor in self?.updateButton() }
    }.store(in: &cancellables)
    model.$lastDrainSummary.sink { [weak self] summary in
      Task { @MainActor in
        guard let self, let summary else { return }
        self.warningVisible = summary.failedCount > 0
        self.updateButton()
      }
    }.store(in: &cancellables)
    model.$toolsAvailable.sink { [weak self] _ in
      Task { @MainActor in self?.updateButton() }
    }.store(in: &cancellables)
  }

  private func updateButton() {
    guard let button = statusItem.button else { return }
    if !model.toolsAvailable || warningVisible {
      button.image = Self.systemImage("exclamationmark.triangle")
    } else if model.snapshot.isRunning {
      button.image = Self.systemImage("arrow.triangle.2.circlepath")
    } else {
      button.image = BrandGlyph.statusItemImage()
    }
    let presentation = StatusItemTextPresentation.make(
      unfinishedCount: model.snapshot.unfinishedCount
    )
    statusItem.length = presentation.length
    button.title = presentation.title
  }

  private static func systemImage(_ name: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: "Convert Anything")
    image?.isTemplate = true
    return image
  }

  private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else {
      showPopover(makeKey: true)
    }
  }

  private func showPopover(makeKey: Bool) {
    guard let button = statusItem.button else { return }
    warningVisible = false
    updateButton()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    guard makeKey, let window = popover.contentViewController?.view.window else { return }
    window.makeKey()
    // Drop the automatic first-responder focus so no footer button
    // (Settings…) appears keyboard-focused when the popover opens.
    window.makeFirstResponder(nil)
  }

  private func beginDragPresentation() {
    if dragPopoverSession.begin(popoverIsShown: popover.isShown) {
      showPopover(makeKey: false)
    }
  }

  private func cancelDragPresentation() {
    if dragPopoverSession.cancel(), popover.isShown {
      popover.performClose(nil)
    }
  }

  private func completeDragPresentation() {
    dragPopoverSession.complete()
  }
}
