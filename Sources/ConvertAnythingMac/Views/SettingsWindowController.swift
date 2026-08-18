import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
  public init(model: AppViewModel) {
    let hostingController = NSHostingController(rootView: SettingsView(model: model))
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Convert Anything Settings"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.setContentSize(NSSize(width: 620, height: 480))
    window.isReleasedWhenClosed = false
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func show() {
    showWindow(nil)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
