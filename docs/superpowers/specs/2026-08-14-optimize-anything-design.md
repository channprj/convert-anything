# Optimize Anything Product Requirements and Design

- **Status:** Approved for implementation
- **Date:** 2026-08-14
- **Repository:** `channprj/optimize-anything` (private)
- **Initial release:** Native Apple Silicon macOS MVP

## 1. Executive Summary

### Problem Statement

Converting media files to storage-efficient formats currently requires opening a
dedicated application, selecting codecs and quality options, choosing output
paths, and repeating the process for every file type. This is unnecessary work
when the desired conversion is predictable from the source extension.

### Proposed Solution

Optimize Anything is a native, Dock-less macOS menu bar utility. A user drops
one or more files directly onto its menu bar item, and the app applies the
enabled source-to-target rule, encodes in a serial background queue with a
bundled FFmpeg toolchain, writes the result next to the source, and posts one
local macOS notification when the queue drains.

The MVP ships with safe defaults and a constrained rule editor:

| Media family | Default sources | Default target | Balanced quality |
| --- | --- | --- | --- |
| Audio | WAV, AIFF, FLAC, CAF | M4A | AAC-LC 160 kbps |
| Video | MOV, MP4, MKV | WebM | VP9 CRF 32 + Opus 96 kbps |
| Image | JPEG, PNG, WebP, TIFF | AVIF | AV1 CRF 30 |

### Success Criteria

1. A supported file dropped on the status item is accepted or rejected with a
   concrete reason within 500 ms, excluding time spent by the drag itself.
2. Every default mapping produces an output whose container and codecs match
   the rule, as verified with `ffprobe` against deterministic fixtures.
3. The output is written beside the source, the source SHA-256 remains
   unchanged, and no temporary file remains after success, failure, or cancel.
4. Rule and quality changes survive an app relaunch without overwriting a later
   intentional user choice when defaults evolve.
5. Each queue-drain event produces exactly one completion summary through
   `UNUserNotificationCenter` when authorized, with an in-app fallback when it
   is not authorized.

## 2. User Experience & Functionality

### User Personas

- **Primary — media-heavy Mac user:** Frequently receives lossless audio,
  camera video, screenshots, or design exports and wants smaller copies without
  opening an editor.
- **Secondary — developer or creator:** Wants deterministic, inspectable format
  rules without remembering FFmpeg flags.

### User Stories

#### Story OA-1 — Convert from the menu bar

As a Mac user, I want to drop files directly on a menu bar target so that I can
start known conversions without opening a window.

**Acceptance Criteria**

- The app runs with no Dock icon and creates one `NSStatusItem`.
- The `NSStatusBarButton` is a registered file URL drag destination.
- Entering with a compatible drag expands the target and shows `Drop to
  optimize`; leaving restores the idle icon.
- Dropping multiple regular files admits every supported file and reports each
  unsupported, missing, or unreadable path without aborting the supported set.
- The same admission behavior is available in the popover drop area for users
  who prefer a larger target.

#### Story OA-2 — Run safe background conversions

As a user, I want conversion to continue in the background without damaging my
originals so that I can return to other work immediately.

**Acceptance Criteria**

- Jobs run serially off the main actor; the UI remains responsive.
- The first available output is `<stem>.<target>`; collisions use
  `<stem>-optimized.<target>`, then `<stem>-optimized-2.<target>` and higher.
- Encoding writes to a unique hidden sibling temporary file and atomically
  moves it to the reserved output only after FFmpeg exits successfully and the
  output is non-empty.
- The app never mutates, renames, replaces, or deletes a source file.
- A current job can be canceled. Cancel terminates the child process, removes
  its temporary output, marks the job canceled, and continues the queue.
- Quitting with active work requires an explicit choice to keep waiting or
  cancel all work.

#### Story OA-3 — Understand progress and results

As a user, I want compact progress and clear outcomes so that I know what the
background utility is doing.

**Acceptance Criteria**

- While work exists, the status item displays the number of unfinished jobs.
- Clicking the item opens a popover containing the active job, queued jobs,
  current-session results, progress, and a short actionable error when needed.
- Successful jobs offer `Show Output`; failed jobs offer `Show Source` and
  `Retry` when retry is safe.
- When the queue becomes empty, one summary reports successful, failed, and
  canceled counts plus bytes saved for successful outputs smaller than their
  sources.
- Clicking the completion notification reveals the last successful output in
  Finder when one exists.

#### Story OA-4 — Configure deterministic rules

As a user, I want safe defaults that I can adjust so that optimization matches
my preferred size-quality tradeoff.

**Acceptance Criteria**

- Settings list rules by media family with source extensions, target format,
  enabled state, and `Smaller`, `Balanced`, or `Higher Quality` preset.
- A user can add, edit, disable, remove, and restore supported rules.
- Target choices are restricted to formats supported for the selected media
  family; arbitrary FFmpeg arguments are not accepted.
- At most one enabled rule may claim a source extension. A conflicting edit is
  blocked with a specific explanation.
- Settings are stored as a versioned local JSON document and written
  atomically.

#### Story OA-5 — Receive native completion feedback

As a user, I want a native macOS notification when all conversions finish so
that I do not need to watch the queue.

**Acceptance Criteria**

- Notification permission is requested just in time on the first accepted
  drop, not at application launch.
- The notification is a local notification and does not require APNs, an
  account, analytics, or any network service.
- Denied or unavailable notification authorization never blocks conversion;
  the popover exposes the same completion summary.
- Additional drops while the queue is active join the current drain summary,
  preventing per-file notification spam.

### Detailed Interaction Contract

The idle status item uses a monochrome SF Symbol. During a compatible drag it
expands to a highlighted `Drop to optimize` target. During conversion it shows
the remaining job count, and after a batch containing failures it temporarily
uses a warning state until the popover has been opened.

The popover contains, in order: product title and aggregate state, active job,
queued jobs, recent session results, then `Settings…`, `Show Output`, and
`Quit`. It does not open automatically after a valid drop. It may open for an
admission error because the user otherwise has no place to read the reason.

Essential presentation semantics such as pixel dimensions, alpha, audio
channels, video orientation, and color characteristics are preserved when the
target supports them. Nonessential source-container metadata is not guaranteed
to survive; the original remains the authority.

### Non-Goals

The MVP intentionally excludes:

- deleting or replacing originals;
- recursive folder drops, watched folders, and Finder Quick Actions;
- arbitrary extension-to-command scripting or free-form FFmpeg arguments;
- cloud sync, accounts, uploads, telemetry, and analytics;
- a permanent conversion-history database;
- automatic updates, Mac App Store distribution, Developer ID notarization,
  and public release automation;
- Intel or universal binaries and non-macOS platforms;
- parallel transcodes and configurable concurrency;
- animated AVIF as a default target for video.

## 3. AI System Requirements (Not Applicable)

Optimize Anything performs deterministic local media conversion. It contains no
AI model, prompt, inference service, training data, evaluation corpus, or remote
tool API. AI-specific tool and evaluation requirements therefore do not apply.

## 4. Technical Specifications

### Architecture Overview

The MVP is a Swift Package that produces a native AppKit/SwiftUI application
bundle targeting Apple Silicon and macOS 14 or later. `NSApplication` runs as an
accessory app and `LSUIElement` suppresses the Dock icon.

```text
NSStatusBarButton / popover drop area
                 |
                 v
          DropAdmissionService
                 |
                 v
  MappingStore -> ConversionPlanner -> OutputPathResolver
                                      |
                                      v
                                ConversionQueue
                                      |
                          FFprobeClient / FFmpegRunner
                                      |
                                      v
                       temporary output -> atomic move
                                      |
                   JobStore -> popover / NotificationService
```

Component boundaries:

- **ApplicationController:** Owns application lifecycle and coordinates shared
  services. It contains no conversion policy.
- **StatusBarController:** Owns `NSStatusItem`, drag feedback, popover
  presentation, and status icon state.
- **DropAdmissionService:** Resolves file URLs, rejects directories and
  unreadable or non-regular inputs, and returns per-path decisions.
- **MappingStore:** Loads defaults, validates edits, performs versioned
  migrations, and atomically persists user rules.
- **ConversionPlanner:** Produces an immutable plan from an input, matching
  rule, quality preset, and reserved output path.
- **OutputPathResolver:** Generates deterministic collision-free final and
  hidden temporary sibling paths.
- **ConversionQueue:** An actor that owns ordering, cancellation, terminal job
  state, and the queue-drain boundary.
- **FFprobeClient:** Reads duration, streams, container, and codec metadata for
  planning, progress, and postcondition checks.
- **FFmpegRunner:** Launches the bundled executable with `Process`, never a
  shell, parses machine-readable progress, and returns structured exit data.
- **NotificationService:** Wraps authorization, local notification delivery,
  and notification click handling behind a testable protocol.
- **JobStore:** Publishes active, queued, and current-session terminal jobs to
  AppKit and SwiftUI without persisting media paths after app termination.

### Core Models and Invariants

`SettingsDocument` has a numeric `schemaVersion` and a list of
`ConversionRule` values. A rule has a stable ID, media family, normalized source
extensions, supported target, quality preset, and enabled state. Migrations are
field-by-field and one-time: they add new defaults without rewriting an existing
user value on every launch.

`ConversionJob` has one of these states:

```text
queued -> probing -> converting -> validating -> succeeded
   |          |          |             |
   +----------+----------+-------------+-> failed
                         |
                         +----------------> canceled
```

Terminal states are immutable. Every admitted input creates exactly one job.
Every job owns a unique temporary path, and only a succeeded job owns a final
output path.

### Encoder Profiles

Profiles use explicit codec and quality arguments instead of FFmpeg defaults.
The concrete values below form the initial contract; settings display friendly
names rather than raw arguments.

| Family | Smaller | Balanced | Higher Quality |
| --- | --- | --- | --- |
| M4A/AAC | 96 kbps | 160 kbps | 256 kbps |
| WebM/VP9 | CRF 38, Opus 64 kbps | CRF 32, Opus 96 kbps | CRF 26, Opus 128 kbps |
| AVIF/AV1 | CRF 38 | CRF 30 | CRF 22 |

Video uses constrained-quality VP9 with zero target bitrate, row-level
multithreading, the source frame rate, and Opus audio when an audio stream is
present. Image conversion preserves source dimensions and alpha when present.
Audio conversion excludes attached video artwork in the MVP to keep the output
contract deterministic.

### Integration Points

- **AppKit:** `NSStatusItem`, `NSStatusBarButton`, `NSDraggingDestination`,
  `NSPopover`, Finder reveal, and application lifecycle.
- **SwiftUI:** Popover contents and settings window.
- **UserNotifications:** Local permission and queue-drain notifications.
- **Foundation:** `Process`, pipes, file coordination, atomic settings writes,
  volume-capacity checks, and child-process cancellation.
- **FFmpeg toolchain:** Pinned `ffmpeg` and `ffprobe` executables live in
  `Contents/Resources`. The app refuses to enqueue conversion if either bundled
  tool is missing or not executable.
- **Finder:** Outputs are written only to the source directory and revealed with
  `NSWorkspace`.

No database, authentication, API server, analytics endpoint, or remote storage
is involved.

### FFmpeg Supply Chain and Licensing

The distributable toolchain is built without `--enable-gpl` and without
`--enable-nonfree`. VP9, AV1, and Opus support use redistributable libvpx,
libaom, and libopus configurations. The build definition pins source versions
and SHA-256 values, records configure arguments, and emits exact corresponding
source and license notices. The repository does not treat the GPL-enabled
FFmpeg already installed on the development machine as a release dependency.

The application About view and `THIRD_PARTY_NOTICES.md` identify FFmpeg and its
license. A release process must make the corresponding source archive available
beside any distributed binary before public distribution is added to scope.

### Error Handling

- **Unsupported source:** Reject before enqueue and name the unsupported
  extension.
- **Unreadable or missing input:** Reject without creating a job.
- **Conflicting or invalid rule:** Prevent settings save and preserve the last
  valid settings document.
- **Insufficient disk space:** Fail preflight before launching FFmpeg. Capacity
  uses the volume's important-usage value and a conservative per-family output
  estimate plus temporary-file margin.
- **FFprobe failure:** Mark the job failed with a concise invalid-media reason
  and retain stderr for local diagnostics.
- **FFmpeg nonzero exit:** Remove the temporary output, classify cancel versus
  failure, and show the final relevant stderr line without exposing raw command
  noise as the primary message.
- **Invalid output:** Treat empty output or mismatched target container/codecs
  as failure even when FFmpeg exits zero.
- **Final move failure:** Preserve the source, record the structured move error,
  remove the temporary output, and never replace an existing final path.
- **Notification denial:** Record an in-app summary only.

### Security & Privacy

- Media bytes and paths stay on the local Mac; there is no network feature.
- Child processes receive an executable URL and argument array directly. User
  paths never enter a shell command.
- Only file URLs from a drag pasteboard or the popover picker are accepted.
- The app resolves symlinks for validation but does not follow a directory as a
  recursive input.
- Logs redact parent directory components by default and retain only the file
  name, job ID, profile, timing, exit status, and structured error category.
- The non-App-Store MVP does not enable App Sandbox. It requests no elevated
  privileges and writes only the output and temporary sibling selected by the
  user's dropped file location.
- Notification text contains file names and aggregate sizes, never full paths.

### Performance and Resource Policy

- Admission, mapping, and queue mutation occur without blocking the main actor
  on media I/O.
- Exactly one FFmpeg process runs at a time in the MVP.
- Progress updates exposed to the UI are coalesced to at most ten per second.
- There is no fixed input-size limit. Disk preflight and filesystem errors
  govern whether a job can start.
- The app keeps only the current session's job summaries and releases captured
  stderr after terminal error classification.

### Testing and Verification Strategy

#### Unit Tests

- extension normalization, compatible-target validation, conflicting rules,
  and one-time settings migrations;
- all nine encoder profile argument sets;
- collision sequences, hidden temporary paths, and no-replacement invariants;
- queue ordering, state transitions, cancellation, retry, and one drain event;
- notification summaries and denied-authorization fallback;
- progress parsing and user-facing FFmpeg error classification.

#### Integration Tests

Deterministic fixtures are generated from FFmpeg filters rather than committed
large binaries: short PCM audio, a short color/test-source video with audio,
an opaque image, and an alpha image. Tests run real bundled-tool commands and
assert with `ffprobe` that:

- WAV becomes M4A containing AAC;
- MOV becomes WebM containing VP9 and Opus;
- PNG becomes AVIF containing AV1;
- pixel size, alpha where applicable, channel count, and orientation contract
  hold;
- every source SHA-256 is unchanged;
- outputs are non-empty and all temporary files are cleaned;
- collision outputs never replace existing bytes;
- a forced failure and cancellation leave no finalized output.

#### App and Runtime Checks

- `swift test` passes under the declared deployment target.
- A release build produces `Optimize Anything.app` with `LSUIElement`, bundled
  executable tools, resources, license notices, and no unexpected dynamic
  library references.
- `codesign --verify --deep --strict` passes for the locally ad-hoc-signed app.
- Launching the app produces one running process, no Dock item, and one menu bar
  item.
- A real Finder drag onto the status item converts each default fixture beside
  its source; the popover reports progress and Finder reveal selects the result.
- Notification behavior is checked with authorization granted and denied. A
  missing macOS permission is reported separately rather than inferred from
  unit tests.

### MVP Definition of Done

The MVP is done only when the private remote contains the approved PRD,
implementation plan, source, tests, reproducible build scripts, FFmpeg supply
chain definition, and license notices; all automated checks pass; an app bundle
builds; the real drag-to-status-item flow produces verified outputs beside the
fixtures without changing sources; a native completion notification is observed
when permission is available; and local `main`, its tracking branch, and the
live GitHub remote are byte-equivalent.

## 5. Risks & Roadmap

### Phased Rollout

#### MVP — Native local utility

- Apple Silicon and macOS 14 or later
- direct menu bar and popover file drop
- bundled reproducible FFmpeg/FFprobe toolchain
- serial queue, progress, cancel, retry, and current-session results
- constrained rule settings with three quality presets
- safe sibling output and local completion notification
- local ad-hoc-signed app bundle and private GitHub development workflow

#### v1.1 — Daily-driver hardening

- Developer ID signing and notarized direct distribution
- universal Apple Silicon and Intel build if demand justifies it
- launch-at-login using `SMAppService.mainApp`
- persistent privacy-conscious history and configurable retention
- controlled concurrency with thermal and power awareness
- additional validated targets such as HEVC MP4 and Opus audio

#### v2.0 — Automation

- recursive folders and watched-folder recipes
- Finder Quick Actions and Shortcuts integration
- reusable named presets and import/export
- signed automatic updates and release-channel controls
- batch policies for metadata, resize, and output location

### Technical Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Menu bar item is a small drop target | Missed drops and unclear affordance | Expand and highlight on drag; provide the identical larger popover target |
| VP9/AV1 encoding is slow | Heat, battery use, perceived stalls | Serial queue, visible progress, cancel, three explicit quality presets |
| FFmpeg build violates redistribution terms | Blocks distribution | Exclude GPL/nonfree options, pin sources/checksums, publish exact notices and source |
| Corrupt media or misleading extension | Encoder failure or invalid output | Probe content, validate terminal output, preserve source, surface structured failure |
| Output volume fills during conversion | Partial artifacts | Conservative capacity preflight, sibling temp file, cleanup on every terminal path |
| Notification permission is denied | User misses completion | Just-in-time request and equivalent persistent in-popover summary |
| Settings schema evolves | User choices are silently reset | Versioned field-by-field one-time migrations with fixtures for every version |
| Local machine lacks full Xcode | Distribution validation unavailable | Build and test MVP with SwiftPM/Command Line Tools; treat notarization as a later credentialed gate |

### Product Risks and Mitigations

- **“Optimize” can imply guaranteed savings.** The result summary reports bytes
  saved but does not delete an output merely because a particular source was
  already smaller. A later setting may allow skipping larger results.
- **Lossy conversion can surprise users.** Format, quality, and the fact that
  originals are retained are visible in settings and every queued job.
- **Metadata expectations vary.** The MVP promises essential presentation
  semantics, not full metadata parity, and preserves the original as authority.
- **Too much configurability recreates FFmpeg.** The editor exposes only tested
  compatibility combinations and named quality presets.
