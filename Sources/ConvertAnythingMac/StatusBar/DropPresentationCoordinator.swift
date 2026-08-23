import Combine
import Foundation

@MainActor
public final class DropPresentationCoordinator: ObservableObject {
  public enum Destination: Hashable, Sendable {
    case statusItem
    case popover
  }

  @Published public private(set) var isActive = false
  public var onActivation: @MainActor () -> Void = {}
  public var onCancellation: @MainActor () -> Void = {}
  public var onCompletion: @MainActor () -> Void = {}

  private let exitGracePeriod: Duration
  private var targetedDestinations: Set<Destination> = []
  private var pendingExit: Task<Void, Never>?

  public init(exitGracePeriod: Duration = .milliseconds(200)) {
    self.exitGracePeriod = exitGracePeriod
  }

  deinit {
    pendingExit?.cancel()
  }

  public func setTargeted(_ targeted: Bool, at destination: Destination) {
    if targeted {
      let inserted = targetedDestinations.insert(destination).inserted
      guard inserted else { return }
      pendingExit?.cancel()
      pendingExit = nil
      if !isActive {
        isActive = true
        onActivation()
      }
      return
    }

    guard targetedDestinations.remove(destination) != nil,
      targetedDestinations.isEmpty,
      isActive
    else { return }

    pendingExit?.cancel()
    let gracePeriod = exitGracePeriod
    pendingExit = Task { [weak self] in
      try? await Task.sleep(for: gracePeriod)
      guard !Task.isCancelled, let self, self.targetedDestinations.isEmpty else { return }
      self.pendingExit = nil
      self.isActive = false
      self.onCancellation()
    }
  }

  public func completeDrop() {
    pendingExit?.cancel()
    pendingExit = nil
    targetedDestinations.removeAll()
    let wasActive = isActive
    isActive = false
    if wasActive { onCompletion() }
  }
}

public struct DragPopoverSession: Sendable {
  private var openedForDrag = false

  public init() {}

  public mutating func begin(popoverIsShown: Bool) -> Bool {
    openedForDrag = !popoverIsShown
    return openedForDrag
  }

  public mutating func cancel() -> Bool {
    defer { openedForDrag = false }
    return openedForDrag
  }

  public mutating func complete() {
    openedForDrag = false
  }
}
