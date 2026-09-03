import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
  public init(model: AppViewModel) {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 620, height: 480)),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    let hostingController = NSHostingController(
      rootView: SettingsView(model: model) { [weak window] in
        window?.close()
      }
    )
    window.contentViewController = hostingController
    window.title = "Convert Anything Settings"
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
