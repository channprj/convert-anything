import AppKit
import Foundation
import OptimizeAnythingMac

let statusBarDropViewTests: [MacTestCase] = [
  MacTestCase("pasteboard extracts only file URLs in original order") {
    try await pasteboardExtractsOnlyFileURLs()
  }
]

@MainActor
private func pasteboardExtractsOnlyFileURLs() throws {
  let pasteboard = NSPasteboard(name: NSPasteboard.Name("optimize-anything-tests"))
  pasteboard.clearContents()
  let first = NSURL(fileURLWithPath: "/tmp/first.wav")
  let second = NSURL(fileURLWithPath: "/tmp/second.mov")
  let values: [any NSPasteboardWriting] = [
    first,
    NSString(string: "not a file URL"),
    second,
  ]
  pasteboard.writeObjects(values)

  let urls = StatusBarDropView.fileURLs(from: pasteboard)

  try macExpectEqual(urls, [first as URL, second as URL])
}
