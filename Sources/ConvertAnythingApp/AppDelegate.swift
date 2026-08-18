import AppKit
import ConvertAnythingMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var controller: ApplicationController?
  private var terminationPending = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = ApplicationController()
    self.controller = controller
    let ingestURLs = Self.ingestURLs(from: ProcessInfo.processInfo.arguments)
    guard !ingestURLs.isEmpty else { return }
    Task { await controller.ingest(ingestURLs) }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model = controller?.model, model.snapshot.unfinishedCount > 0 else {
      return .terminateNow
    }
    guard !terminationPending else { return .terminateLater }
    terminationPending = true

    let alert = NSAlert()
    alert.messageText = "Conversions are still running"
    alert.informativeText = "Keep waiting, or cancel unfinished jobs before quitting."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Keep Waiting")
    alert.addButton(withTitle: "Cancel Jobs and Quit")

    guard alert.runModal() == .alertSecondButtonReturn else {
      terminationPending = false
      return .terminateCancel
    }

    Task { @MainActor in
      for job in model.snapshot.jobs where !job.state.isTerminal {
        await model.cancel(jobID: job.id)
      }
      let clock = ContinuousClock()
      let deadline = clock.now.advanced(by: .seconds(15))
      while model.snapshot.unfinishedCount > 0, clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(100))
      }
      terminationPending = false
      sender.reply(toApplicationShouldTerminate: model.snapshot.unfinishedCount == 0)
    }
    return .terminateLater
  }

  private static func ingestURLs(from arguments: [String]) -> [URL] {
    guard let marker = arguments.firstIndex(of: "--ingest") else { return [] }
    return arguments[arguments.index(after: marker)...].compactMap { path in
      guard path.hasPrefix("/") else { return nil }
      return URL(fileURLWithPath: path).standardizedFileURL
    }
  }
}
