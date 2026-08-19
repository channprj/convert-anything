import AppKit
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation

let statusBarDropViewTests: [TestCase] = [
  TestCase("pasteboard extracts only file URLs in original order") {
    try await pasteboardExtractsOnlyFileURLs()
  }
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
