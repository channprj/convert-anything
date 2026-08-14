import AppKit

public struct FinderService: FinderServing {
  public init() {}

  @MainActor
  public func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
