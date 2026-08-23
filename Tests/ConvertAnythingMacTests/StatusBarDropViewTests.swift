import AppKit
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation

let statusBarDropViewTests: [TestCase] = [
  TestCase("pasteboard extracts only file URLs in original order") {
    try await pasteboardExtractsOnlyFileURLs()
  },
  TestCase("status item presentation has no drag-only expansion") {
    let idle = StatusItemTextPresentation.make(unfinishedCount: 0)
    try expectEqual(idle.length, NSStatusItem.squareLength)
    try expectEqual(idle.title, "")

    let running = StatusItemTextPresentation.make(unfinishedCount: 3)
    try expectEqual(running.length, NSStatusItem.variableLength)
    try expectEqual(running.title, " 3")
  },
]

@MainActor
private func pasteboardExtractsOnlyFileURLs() throws {
  let pasteboard = NSPasteboard(name: NSPasteboard.Name("convert-anything-tests"))
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

  try expectEqual(urls, [first as URL, second as URL])
}
