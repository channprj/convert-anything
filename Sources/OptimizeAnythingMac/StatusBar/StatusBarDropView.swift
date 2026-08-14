import AppKit

public final class StatusBarDropView: NSView {
  public var onClick: @MainActor () -> Void = {}
  public var onDragActiveChanged: @MainActor (Bool) -> Void = { _ in }
  public var onDropURLs: @MainActor ([URL]) -> Void = { _ in }

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    let urls = Self.fileURLs(from: sender.draggingPasteboard)
    guard !urls.isEmpty else { return [] }
    onDragActiveChanged(true)
    return .copy
  }

  public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    onDragActiveChanged(false)
  }

  public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let urls = Self.fileURLs(from: sender.draggingPasteboard)
    onDragActiveChanged(false)
    guard !urls.isEmpty else { return false }
    onDropURLs(urls)
    return true
  }

  public override func mouseDown(with event: NSEvent) {
    onClick()
  }

  public static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
  }
}
