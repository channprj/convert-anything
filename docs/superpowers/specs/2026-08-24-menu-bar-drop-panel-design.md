# Menu Bar Drop Panel Design

- **Status:** Approved for implementation
- **Date:** 2026-08-24
- **Repository:** `channprj/convert-anything`
- **Scope:** macOS status-item and popover drag feedback

## 1. Problem and Goal

The status item currently accepts file URLs through a target approximately the
size of the menu bar icon. After the pointer reaches that small target, the item
expands horizontally to 142 points and shows `Drop to convert`. The expansion
still has the menu bar's limited height, shifts neighboring menu bar items, and
does not provide the large, obvious destination the user wants.

When a valid file drag reaches the Convert Anything status item, the existing
360-by-430-point popover will open automatically and become the visible drop
surface. The queue and controls remain visible while a strong border, subtle
accent wash, and `Drop to convert` label make the entire panel read as the
target.

This document supersedes the drag-feedback parts of
`2026-08-14-optimize-anything-design.md`: a compatible drag no longer expands
the status item, and the popover may open automatically before a drop.

## 2. Success Criteria

1. Entering the status item with one or more file URLs opens the popover and
   exposes the full-panel drop treatment without requiring a click.
2. The status item does not change to the drag-only 142-point label, so nearby
   menu bar items do not move because of drag feedback.
3. Moving from the status item into the popover does not dismiss or flicker the
   panel during the AppKit-to-SwiftUI drag-destination handoff.
4. Existing queue rows, progress, errors, and footer controls remain visible
   beneath the non-interactive drop treatment.
5. A successful drop removes the treatment, submits each URL exactly once, and
   leaves the popover open so conversion progress or admission errors are
   visible.
6. Leaving both the status item and popover without dropping closes only a
   popover that this drag opened. A popover the user had already opened remains
   open.
7. Non-file drags do not activate the panel, and click-to-toggle behavior is
   unchanged.
8. Automatic presentation does not activate the app or move keyboard focus
   away from the drag source.

## 3. Selected Experience

### Entry

`StatusBarDropView` continues to validate the drag pasteboard before accepting
it. When at least one file URL enters, drag presentation becomes active and the
popover opens immediately. The status item keeps its normal icon or unfinished
job count; it does not adopt a drag-only width or title. Automatic presentation
does not make the popover key or activate Convert Anything, so the source Finder
window keeps focus during the drag. Manual click-to-open behavior retains its
current focus handling.

### Active Drop Treatment

The existing popover remains the drop destination. While targeted, it gains a
non-interactive overlay with:

- a 3-point rounded accent-color border following the popover content bounds;
- a low-opacity accent wash that preserves text and progress readability; and
- a compact bottom-centered pill containing a downward document symbol and
  `Drop to convert`.

The overlay does not replace or blur the queue. It uses semantic system colors
and does not require motion to communicate state. It does not accept pointer
events, so the underlying full-popover drop destination remains authoritative.

### Destination Handoff

The pointer leaves the narrow AppKit status-item destination just before it
enters the SwiftUI popover destination. Both destinations report their targeted
state to one shared presentation coordinator. When the last destination exits,
the coordinator waits 200 milliseconds before deactivating. Entering either
destination during that interval cancels deactivation. This grace period is
only for presentation continuity; it does not delay a completed drop.

### Drop and Cancel

On a drop, presentation state resets before the URLs are passed to
`AppViewModel.handleDrop(_:)`. The popover stays open regardless of whether the
files are accepted, allowing the existing queue or admission errors to explain
the result.

When the drag leaves without dropping and neither destination becomes targeted
during the grace period, the overlay disappears. The controller closes the
popover only if it recorded that the current drag opened it. Manual popover
state is never overwritten by a canceled drag.

## 4. Architecture

A small main-actor presentation coordinator will own drag-source state and the
handoff delay. It is UI state, not conversion state, and therefore will not add
policy to `ConvertAnythingCore`.

```text
StatusBarDropView targeted -----+
                                |
                                v
                    DropPresentationCoordinator
                                |
PopoverView targeted -----------+
                                |
                    +-----------+-----------+
                    |                       |
                    v                       v
          StatusBarController         PopoverView
          open/conditional close      border + wash + label
```

Responsibilities:

- **StatusBarDropView:** Extract file URLs, report status-item targeting, and
  deliver status-item drops as it does today.
- **DropPresentationCoordinator:** Track whether the status item or popover is
  targeted, publish whether the treatment is active, bridge the short handoff,
  and distinguish cancel from completed drop.
- **StatusBarController:** Open the popover on first activation, record whether
  it was already open, conditionally close after cancellation, and stop
  changing the status-item length for drag-only feedback.
- **PopoverView:** Report SwiftUI targeting, render the non-interactive overlay,
  complete popover drops, and retain the existing URL handling path.
- **AppViewModel:** Continue to own admission, conversion submission, queue
  state, and errors. Drag presentation no longer needs to live in this model.

The coordinator is injected into both the controller and the hosted SwiftUI
view. It cancels any pending deactivation task when a new target enters and on
deinitialization, preventing late UI mutations.

## 5. State Contract

```text
idle
  -> status item entered
active + popover opened (or recognized as already open)
  -> status item exited, popover entered within 200 ms
active + popover targeted
  -> drop
idle + popover remains open

active
  -> all destinations exited for 200 ms without drop
idle + auto-opened popover closes
idle + pre-existing popover remains open
```

Repeated target callbacks are idempotent. A completed drop cancels pending
deactivation and cannot also be classified as a canceled drag. Multiple file
URLs remain one drop event and are forwarded in their pasteboard order.

## 6. Edge Cases and Accessibility

- An empty or non-file pasteboard never opens the popover.
- Dragging across the popover border repeatedly only updates presentation; it
  never submits files until a drop occurs.
- Dropping unsupported file types still leaves the popover open so existing
  per-file admission errors are visible.
- If the popover is manually closed while a drag is active, the controller does
  not repeatedly reopen it until a new valid status-item entry begins.
- The overlay uses the system accent color and remains understandable without
  animation. The label includes text rather than relying on color alone.
- The decorative overlay is hidden from accessibility traversal to avoid
  duplicating the underlying drop destination. The destination exposes a
  concise `Drop files to convert` accessibility description.

## 7. Testing and Verification

### Automated Tests

- Coordinator tests cover status entry, the 200-millisecond handoff, re-entry,
  canceled auto-open, canceled pre-opened popover, completed drops, repeated
  callbacks, and pending-task cancellation.
- `StatusBarDropView` tests retain pasteboard order and verify that non-file
  values cannot activate file-drag presentation.
- `PopoverView` hosting tests verify that the targeted treatment spans the
  popover while footer controls remain laid out and discoverable.
- Controller-facing tests verify that drag presentation does not assign the
  142-point status-item width or drag-only title.

### Repository Gates

Run the focused macOS test executable while iterating, then the repository's
full check:

```bash
swift run ConvertAnythingMacTests
zsh scripts/check.sh
```

The full check covers formatting, core and macOS tests, release compilation,
app assembly, real media conversion, runtime smoke, packaging, and
`git diff --check`.

### Packaged-App QA

Launch `dist/Convert Anything.app` and drag a real supported fixture from
Finder to the status item. Confirm visually that the popover opens, the full
border treatment is obvious, the queue stays readable, the status-item width
does not jump, cancel closes only an auto-opened popover, and a real drop keeps
the popover open while producing the expected output. Record any macOS
automation, Accessibility, or screen-capture limitation separately rather than
substituting source-level evidence for native UI proof.

## 8. Non-Goals

- A permanent wide status item or an always-visible drop label.
- A new floating panel or screen-wide drop shelf.
- Changes to admission rules, conversion formats, queue behavior, output
  naming, notifications, or settings.
- Folder drops, watched folders, Finder extensions, or global drag monitoring.
- Redesigning the popover's queue rows, header, or footer.
