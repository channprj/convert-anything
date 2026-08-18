import AppKit
import Combine
import SwiftUI

@MainActor
public final class StatusBarController {
  private let statusItem: NSStatusItem
  private let popover = NSPopover()
  private let model: AppViewModel
  private let dropView: StatusBarDropView
  private var cancellables = Set<AnyCancellable>()
  private var warningVisible = false

  public init(
    model: AppViewModel,
    onSettings: @escaping @MainActor () -> Void,
    onQuit: @escaping @MainActor () -> Void
  ) {
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    dropView = StatusBarDropView(frame: .zero)

    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 430)
    popover.contentViewController = NSHostingController(
      rootView: PopoverView(model: model, onSettings: onSettings, onQuit: onQuit)
    )

    configureButton()
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
    dropView.onDragActiveChanged = { [weak self] active in
      self?.model.isDragActive = active
      self?.updateButton()
    }
    dropView.onDropURLs = { [weak self] urls in
      guard let self else { return }
      Task { await self.model.handleDrop(urls) }
    }
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
    if model.isDragActive {
      statusItem.length = 142
      button.image = nil
      button.title = "Drop to convert"
      return
    }

    let symbolName: String
    if !model.toolsAvailable || warningVisible {
      symbolName = "exclamationmark.triangle"
    } else if model.snapshot.isRunning {
      symbolName = "arrow.triangle.2.circlepath"
    } else {
      symbolName = "arrow.down.right.and.arrow.up.left"
    }
    button.image = NSImage(
      systemSymbolName: symbolName, accessibilityDescription: "Convert Anything")
    button.image?.isTemplate = true
    if model.snapshot.unfinishedCount > 0 {
      statusItem.length = NSStatusItem.variableLength
      button.title = " \(model.snapshot.unfinishedCount)"
    } else {
      statusItem.length = NSStatusItem.squareLength
      button.title = ""
    }
  }

  private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      warningVisible = false
      updateButton()
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }
}
