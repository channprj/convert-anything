# Menu Bar Drop Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing status-item file target into a large, obvious popover drop surface without shifting menu bar items or hiding current conversion progress.

**Architecture:** A main-actor `DropPresentationCoordinator` will merge targeted-state callbacks from the AppKit status item and SwiftUI popover, hold the active state across a 200-millisecond destination handoff, and distinguish cancellation from a completed drop. `StatusBarController` will own automatic popover lifecycle, while `PopoverView` will keep the existing queue visible beneath a non-interactive full-panel treatment.

**Tech Stack:** Swift 6.2, AppKit `NSStatusItem`/`NSPopover`/`NSDraggingDestination`, SwiftUI `dropDestination`, Combine `ObservableObject`, the repository's executable Swift test harness, and zsh acceptance scripts.

## Global Constraints

- Target macOS 14 or later and preserve the existing Dock-less `LSUIElement` application model.
- Open the existing 360-by-430-point popover only after a pasteboard yields at least one file URL.
- Do not assign the drag-only 142-point status-item length or `Drop to convert` button title.
- Do not activate Convert Anything or make the popover key when it opens automatically; preserve the drag source's keyboard focus.
- Keep queue rows, progress, admission errors, header, and footer visible while targeted.
- Use one 200-millisecond grace period between the status-item and popover destinations; a completed drop bypasses the delay.
- Keep the popover open after a completed drop, including an unsupported-file drop that produces admission errors.
- Close on cancellation only when the current drag opened the popover; preserve a manually opened popover.
- Preserve URL order and forward a multi-file drop exactly once through `AppViewModel.handleDrop(_:)`.
- Keep drag presentation in `ConvertAnythingMac`; do not add UI policy to `ConvertAnythingCore` or conversion state to `AppViewModel`.
- Use semantic system accent colors, visible text in addition to color, no required animation, and a non-interactive decorative overlay.
- Under `$gcpr`, stage explicit paths, create only green Conventional Commit checkpoints, push each immediately, and require `HEAD...@{u}` to report `0 0` before starting the next task.

---

## File and Responsibility Map

```text
Sources/ConvertAnythingMac/
  StatusBar/
    DropPresentationCoordinator.swift  # targeted destinations, grace delay, completion/cancel
    StatusBarDropView.swift             # AppKit file target and accessibility help
    StatusBarController.swift           # status item plus manual/automatic popover lifecycle
  Views/
    PopoverView.swift                   # SwiftUI targeting and full-panel visual treatment
  AppViewModel.swift                    # remove obsolete drag-presentation property only
Tests/ConvertAnythingMacTests/
  DropPresentationCoordinatorTests.swift # state, handoff, completion, lifecycle policy
  StatusBarDropViewTests.swift           # pasteboard and status-item presentation contract
  PopoverViewTests.swift                 # overlay visibility and existing-control preservation
  TestMain.swift                         # register the added macOS tests
scripts/check.sh                         # keep the authoritative macOS test total accurate
USAGE.md                                # keep the documented macOS test total accurate
```

The implementation has two code checkpoints:

| Task | Commit | Independently reviewable outcome |
| --- | --- | --- |
| 1 | `feat(macos): auto-open popover for file drags` | A valid status-item drag opens a stable large destination, hands off to the popover, and preserves manual popover lifecycle without menu bar expansion. |
| 2 | `feat(macos): highlight popover drop target` | The large destination is unmistakable while its queue remains visible, and the packaged app passes the full acceptance chain. |

### Task 1: Coordinate Drag Presentation and Automatic Popover Lifecycle

**Files:**
- Create: `Sources/ConvertAnythingMac/StatusBar/DropPresentationCoordinator.swift`
- Create: `Tests/ConvertAnythingMacTests/DropPresentationCoordinatorTests.swift`
- Modify: `Sources/ConvertAnythingMac/StatusBar/StatusBarDropView.swift:3-44`
- Modify: `Sources/ConvertAnythingMac/StatusBar/StatusBarController.swift:6-115`
- Modify: `Sources/ConvertAnythingMac/Views/PopoverView.swift:4-33`
- Modify: `Sources/ConvertAnythingMac/AppViewModel.swift:47-55`
- Modify: `Tests/ConvertAnythingMacTests/StatusBarDropViewTests.swift:6-28`
- Modify: `Tests/ConvertAnythingMacTests/PopoverViewTests.swift:19-36`
- Modify: `Tests/ConvertAnythingMacTests/TestMain.swift:5-9`

**Interfaces:**
- Consumes: `StatusBarDropView.onClick`, `StatusBarDropView.onDropURLs`, `NSPopover.isShown`, `NSPopover.show(relativeTo:of:preferredEdge:)`, and `PopoverView.dropDestination(for:action:isTargeted:)`.
- Produces: `DropPresentationCoordinator.Destination`, `setTargeted(_:at:)`, `completeDrop()`, `isActive`, `onActivation`, `onCancellation`, `onCompletion`, and `DragPopoverSession.begin(popoverIsShown:)`/`cancel()`/`complete()` for Task 2 and controller integration.

- [ ] **Step 1: Add failing coordinator and popover-session tests**

Create `DropPresentationCoordinatorTests.swift`, register its array in
`TestMain`, and cover activation, handoff, cancellation, completion, idempotence,
and manual-popover preservation with short test-only grace periods:

```swift
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation

let dropPresentationCoordinatorTests: [TestCase] = [
  TestCase("drop presentation bridges status item to popover") {
    try await presentationBridgesDestinations()
  },
  TestCase("drop presentation cancels after every destination exits") {
    try await presentationCancelsAfterGracePeriod()
  },
  TestCase("completed drop never reports cancellation") {
    try await completedDropDoesNotCancel()
  },
  TestCase("drag popover session closes only an auto-opened popover") {
    try await dragPopoverSessionPreservesManualPresentation()
  },
]

@MainActor
private func presentationBridgesDestinations() async throws {
  let coordinator = DropPresentationCoordinator(exitGracePeriod: .milliseconds(30))
  var activationCount = 0
  var cancellationCount = 0
  coordinator.onActivation = { activationCount += 1 }
  coordinator.onCancellation = { cancellationCount += 1 }

  coordinator.setTargeted(true, at: .statusItem)
  coordinator.setTargeted(false, at: .statusItem)
  try await Task.sleep(for: .milliseconds(10))
  coordinator.setTargeted(true, at: .popover)
  try await Task.sleep(for: .milliseconds(40))

  try expectTrue(coordinator.isActive)
  try expectEqual(activationCount, 1)
  try expectEqual(cancellationCount, 0)
}

@MainActor
private func presentationCancelsAfterGracePeriod() async throws {
  let coordinator = DropPresentationCoordinator(exitGracePeriod: .milliseconds(20))
  var cancellationCount = 0
  coordinator.onCancellation = { cancellationCount += 1 }

  coordinator.setTargeted(true, at: .statusItem)
  coordinator.setTargeted(true, at: .statusItem)
  coordinator.setTargeted(false, at: .statusItem)
  try await Task.sleep(for: .milliseconds(40))

  try expectTrue(!coordinator.isActive)
  try expectEqual(cancellationCount, 1)
}

@MainActor
private func completedDropDoesNotCancel() async throws {
  let coordinator = DropPresentationCoordinator(exitGracePeriod: .milliseconds(20))
  var completionCount = 0
  var cancellationCount = 0
  coordinator.onCompletion = { completionCount += 1 }
  coordinator.onCancellation = { cancellationCount += 1 }

  coordinator.setTargeted(true, at: .popover)
  coordinator.setTargeted(false, at: .popover)
  coordinator.completeDrop()
  try await Task.sleep(for: .milliseconds(40))

  try expectTrue(!coordinator.isActive)
  try expectEqual(completionCount, 1)
  try expectEqual(cancellationCount, 0)
}

@MainActor
private func dragPopoverSessionPreservesManualPresentation() throws {
  var autoOpened = DragPopoverSession()
  try expectTrue(autoOpened.begin(popoverIsShown: false))
  try expectTrue(autoOpened.cancel())

  var preOpened = DragPopoverSession()
  try expectTrue(!preOpened.begin(popoverIsShown: true))
  try expectTrue(!preOpened.cancel())

  var completed = DragPopoverSession()
  try expectTrue(completed.begin(popoverIsShown: false))
  completed.complete()
  try expectTrue(!completed.cancel())
}
```

- [ ] **Step 2: Run the macOS test target and confirm the missing-type failure**

Run:

```bash
swift run ConvertAnythingMacTests
```

Expected: compilation fails because `DropPresentationCoordinator` and
`DragPopoverSession` do not exist.

- [ ] **Step 3: Implement the isolated presentation state machine**

Create `DropPresentationCoordinator.swift` with this public contract and logic:

```swift
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
```

- [ ] **Step 4: Run the focused tests and confirm the state machine passes**

Run: `swift run ConvertAnythingMacTests`

Expected: the four new cases pass together with the existing six macOS cases.

- [ ] **Step 5: Add a failing status-item presentation contract**

Extend `StatusBarDropViewTests.swift` with a case that requires status-item text
to depend only on unfinished work, never drag state:

```swift
TestCase("status item presentation has no drag-only expansion") {
  let idle = StatusItemTextPresentation.make(unfinishedCount: 0)
  try expectEqual(idle.length, NSStatusItem.squareLength)
  try expectEqual(idle.title, "")

  let running = StatusItemTextPresentation.make(unfinishedCount: 3)
  try expectEqual(running.length, NSStatusItem.variableLength)
  try expectEqual(running.title, " 3")
}
```

Run: `swift run ConvertAnythingMacTests`

Expected: compilation fails because `StatusItemTextPresentation` does not exist.

- [ ] **Step 6: Connect both drag destinations and refactor popover presentation**

Make these exact integration changes:

1. Add `StatusItemTextPresentation` beside `StatusBarController`, use it from
   `updateButton()`, and remove the `model.isDragActive` branch and the 142-point
   constant.
2. Remove `isDragActive` from `AppViewModel`; presentation state now belongs to
   `DropPresentationCoordinator`.
3. Rename `StatusBarDropView.onDragActiveChanged` to `onTargetedChanged`, set an
   accessibility help string of `Drop files to convert`, and keep file URL
   validation and pasteboard order unchanged.
4. Pass one coordinator instance into `PopoverView`, call
   `setTargeted(_:at: .popover)` from the existing SwiftUI drop destination,
   and call `completeDrop()` before `model.handleDrop(_:)`.
5. Wire status targeting to `.statusItem`; call `completeDrop()` before handling
   a status-item drop.
6. Split manual and automatic popover opening so only manual opening makes the
   window key:

```swift
public struct StatusItemTextPresentation: Equatable {
  public let length: CGFloat
  public let title: String

  public static func make(unfinishedCount: Int) -> Self {
    if unfinishedCount > 0 {
      return Self(length: NSStatusItem.variableLength, title: " \(unfinishedCount)")
    }
    return Self(length: NSStatusItem.squareLength, title: "")
  }
}
```

Use the shared coordinator in `PopoverView` without changing the existing drop
submission path:

```swift
.dropDestination(for: URL.self) { urls, _ in
  guard !urls.isEmpty else { return false }
  dropPresentation.completeDrop()
  Task { await model.handleDrop(urls) }
  return true
} isTargeted: { active in
  dropPresentation.setTargeted(active, at: .popover)
}
```

Refactor controller presentation with this focus-preserving split:

```swift
private func showPopover(makeKey: Bool) {
  guard let button = statusItem.button else { return }
  warningVisible = false
  updateButton()
  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  guard makeKey, let window = popover.contentViewController?.view.window else { return }
  window.makeKey()
  window.makeFirstResponder(nil)
}

private func beginDragPresentation() {
  if dragPopoverSession.begin(popoverIsShown: popover.isShown) {
    showPopover(makeKey: false)
  }
}

private func cancelDragPresentation() {
  if dragPopoverSession.cancel(), popover.isShown {
    popover.performClose(nil)
  }
}

private func completeDragPresentation() {
  dragPopoverSession.complete()
}
```

Configure `onActivation`, `onCancellation`, and `onCompletion` after the
controller has initialized the popover and hosted view:

```swift
dropPresentation.onActivation = { [weak self] in self?.beginDragPresentation() }
dropPresentation.onCancellation = { [weak self] in self?.cancelDragPresentation() }
dropPresentation.onCompletion = { [weak self] in self?.completeDragPresentation() }
```

Update every
`PopoverView` initializer in tests to pass the coordinator explicitly.

- [ ] **Step 7: Run Task 1 gates**

Run:

```bash
swift format lint --strict --recursive Package.swift Sources Tests
swift run ConvertAnythingMacTests
git diff --check
```

Expected: eleven macOS tests pass, formatting is clean, and no diff errors remain.

- [ ] **Step 8: Review, commit, push, and prove parity**

Review the complete Task 1 diff, stage only its named source and test paths, and
commit:

```bash
git commit -m "feat(macos): auto-open popover for file drags"
git push
git rev-list --left-right --count HEAD...@{u}
```

Expected: push succeeds and parity prints `0 0` before Task 2 begins.

### Task 2: Render the Large Target and Verify the Packaged Experience

**Files:**
- Modify: `Sources/ConvertAnythingMac/Views/PopoverView.swift:19-33`
- Modify: `Tests/ConvertAnythingMacTests/PopoverViewTests.swift:8-65`
- Modify: `scripts/check.sh:19`
- Modify: `USAGE.md:83-99,164-176`

**Interfaces:**
- Consumes: `DropPresentationCoordinator.isActive` and the coordinator-injected `PopoverView` from Task 1.
- Produces: `PopoverDropTreatment`, the visible `Drop to convert` full-panel treatment, one new hosting test, and accurate totals of twelve macOS adapter tests.

- [ ] **Step 1: Add a failing targeted-popover hosting test**

Add a second `PopoverViewTests` case. Reuse a local `makeModel()` helper for the
existing and new cases, then assert both the treatment copy and original footer
controls render while active:

```swift
TestCase("targeted popover highlights the full drop area without hiding controls") {
  try await targetedPopoverKeepsControlsVisible()
}

@MainActor
private func targetedPopoverKeepsControlsVisible() throws {
  _ = NSApplication.shared
  let size = NSSize(width: 360, height: 430)
  let model = makeModel()
  let presentation = DropPresentationCoordinator(exitGracePeriod: .seconds(1))
  presentation.setTargeted(true, at: .popover)
  let host = NSHostingView(
    rootView: PopoverView(
      model: model,
      dropPresentation: presentation,
      onSettings: {},
      onQuit: {}
    )
  )
  host.frame = NSRect(origin: .zero, size: size)
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  host.layoutSubtreeIfNeeded()

  let labels = descendants(of: host).compactMap { ($0 as? NSTextField)?.stringValue }
  let buttons = descendants(of: host).compactMap { ($0 as? NSButton)?.title }
  try expectTrue(labels.contains("Drop to convert"))
  try expectTrue(buttons.contains("Settings…"))
  try expectTrue(buttons.contains("Quit"))
}

@MainActor
private func makeModel() -> AppViewModel {
  AppViewModel(
    dependencies: ViewModelDependencies(
      settings: FakeSettingsStore(),
      admission: FakeAdmissionService(),
      planner: FakePlanner(),
      queue: FakeQueue(),
      notifications: FakeNotificationService(),
      finder: FakeFinderService()
    )
  )
}
```

Run: `swift run ConvertAnythingMacTests`

Expected: the new test fails because no `Drop to convert` treatment is rendered.

- [ ] **Step 2: Implement the non-interactive full-panel treatment**

Add the overlay after the existing `dropDestination` modifier and keep the
drop destination beneath it:

```swift
.overlay {
  if dropPresentation.isActive {
    PopoverDropTreatment()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
```

Implement the focused view in the same file:

```swift
private struct PopoverDropTreatment: View {
  var body: some View {
    ZStack(alignment: .bottom) {
      Color.accentColor.opacity(0.08)
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.accentColor, lineWidth: 3)
      Label("Drop to convert", systemImage: "arrow.down.doc")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule().stroke(Color.accentColor.opacity(0.45))
        }
        .padding(.bottom, 16)
    }
  }
}
```

Do not add an animation dependency; the border, wash, icon, and text must convey
the state immediately and work with reduced-motion settings.

- [ ] **Step 3: Run the focused visual-contract tests**

Run:

```bash
swift format lint --strict --recursive Sources Tests
swift run ConvertAnythingMacTests
```

Expected: all twelve macOS tests pass; the new test finds the drop label plus
the untouched `Settings…` and `Quit` controls.

- [ ] **Step 4: Update the truthful test totals**

Change the macOS count from 6 to 12 in `scripts/check.sh` and both occurrences
in `USAGE.md`. Do not change the core or integration totals.

Verify:

```bash
rg -n "12 macOS|12 macOS adapter tests" scripts/check.sh USAGE.md
rg -n "6 macOS|6 macOS adapter tests" scripts/check.sh USAGE.md
```

Expected: the new total appears in all three places and the old total appears
nowhere in those files.

- [ ] **Step 5: Run the complete repository acceptance gate**

Quit any running `ConvertAnything` process, then run:

```bash
zsh scripts/check.sh
```

Expected: formatting, installer checks, 76 core tests, 12 macOS tests, release
build, app assembly, 10 real-media integration tests, packaged runtime smoke,
packaging/signature verification, and `git diff --check` all pass. The artifact
is `dist/Convert Anything.app`.

- [ ] **Step 6: Verify the real packaged drag experience**

Launch `dist/Convert Anything.app` and use a generated supported fixture from
Finder. Verify the full user-facing chain:

1. Drag onto the status item without clicking; the popover opens without moving
   neighboring menu bar items or taking Finder focus.
2. Move between the status item and popover; the treatment does not flicker or
   close during the handoff.
3. Leave without dropping; an auto-opened popover closes after the grace period.
4. Open the popover manually, repeat the canceled drag, and confirm it remains
   open.
5. Drop the file; the overlay clears, the popover remains open, and the queue or
   admission result appears exactly once.
6. Confirm the border, wash, icon, and label are obvious while the existing
   queue, progress, and footer remain readable.

If macOS Accessibility or GUI automation cannot perform the physical drag,
record that limitation explicitly and do not present hosting tests or the
runtime conversion smoke as native status-item pixel proof.

- [ ] **Step 7: Review, commit, push, and complete the audit**

Review the full Task 2 diff, run `git diff --check`, stage only the named source,
test, script, and usage files, and commit:

```bash
git commit -m "feat(macos): highlight popover drop target"
git push
git rev-list --left-right --count HEAD...@{u}
```

Then re-read all eight success criteria in the approved design, inspect the
packaged artifact evidence, confirm `.superpowers/` remains the only known
untracked local artifact, and require final parity `0 0`.
