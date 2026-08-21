# Convert Anything Architecture

## Overview

Convert Anything is a Swift 6.2 macOS 14 application composed as three Swift Package Manager products:

- `ConvertAnythingCore` owns media rules, admission, planning, queueing, process execution, and output validation without depending on AppKit.
- `ConvertAnythingMac` owns AppKit and SwiftUI adapters, application composition, settings, notifications, Finder integration, and menu bar presentation.
- `ConvertAnythingApp` provides the `NSApplication` entry point and termination lifecycle.

The application bundles arm64 `ffmpeg` and `ffprobe` executables. Conversion happens locally and serially, while the UI observes queue snapshots and drain summaries through `AsyncStream`.

## Components

| Component | Responsibility |
| --- | --- |
| `ConvertAnythingApp` | Starts the agent-style menu bar application, accepts the internal `--ingest` smoke-test entry point, and coordinates safe termination while jobs are unfinished. |
| `ApplicationController` | Creates the settings store, process executor, probe, encoder runner, conversion service, serial queue, notification adapter, Finder adapter, view model, settings window, and status item. |
| `StatusBarController` and SwiftUI views | Accept file drops, present queue state and progress, expose job actions, and edit conversion rules. |
| `AppViewModel` | Connects UI actions to admission, planning, queue, settings, notifications, and Finder services. It converts domain failures into user-facing messages. |
| `MappingStore` and `RuleCatalog` | Persist versioned JSON rules atomically, migrate older documents, validate rule compatibility, and supply defaults. |
| `DropAdmissionService` | Resolves symlinks and admits only readable regular files with an extension claimed by one enabled rule. |
| `ConversionPlanner` and `OutputPathResolver` | Check conservative free-space requirements and reserve collision-free final and hidden temporary sibling paths. |
| `ConversionQueue` | Runs one job at a time, manages cancellation and retry, publishes snapshots, and produces one aggregate summary after the queue drains. |
| `ConversionService` | Probes the input, invokes FFmpeg, validates the non-empty result, atomically promotes it to the final path, and cleans temporary files. |
| `FFprobeClient`, `FFmpegRunner`, and `FoundationCommandExecutor` | Execute bundled tools directly with argument arrays, parse metadata and progress, capture diagnostics, and terminate active processes. |
| Build and verification scripts | Reproduce the pinned media toolchain, assemble and ad-hoc sign the app, install it, and exercise unit, integration, packaging, and runtime behavior. |

## Data flow

1. `ApplicationController` resolves bundled `ffmpeg` and `ffprobe`, opens the settings store, and publishes the initial default or persisted rules through `AppViewModel`.
2. A drop on the status item or popover reaches `AppViewModel.handleDrop`.
3. `DropAdmissionService` resolves each URL and rejects missing, non-regular, unreadable, extensionless, or unsupported inputs.
4. `ConversionPlanner` checks the enabled rule, reads the allocated source size, reserves a conservative disk-space estimate plus 64 MiB, and asks `OutputPathResolver` for final and hidden temporary sibling paths.
5. Accepted plans enter `ConversionQueue`. The actor drains queued IDs serially and publishes the `queued → probing → converting → validating → terminal` state transitions.
6. `ConversionService` uses `ffprobe` to inspect the input. For WebP, alpha detection settles whether the dynamic target is PNG or JPG.
7. `EncoderArguments` builds a fixed argument array for the selected target and quality preset. `FFmpegRunner` reports progress parsed from FFmpeg's `-progress pipe:1` output.
8. The encoded hidden temporary file must be a non-empty regular file. A second probe verifies the expected container, codec, dimensions, orientation, channel count, and alpha contract where applicable.
9. Only a validated output is moved to the reserved final name. The source is never renamed, replaced, modified, or deleted, and temporary output is removed on failure or cancellation.
10. Queue snapshots update the popover. When the queue drains, the view model retains a success/failure/cancellation summary and sends one local notification when permission is available.

## Directory structure

```text
.
├── App/                         # Info.plist and committed application icon
├── Dependencies/ffmpeg/         # Pinned upstream versions, URLs, and SHA-256 hashes
├── Sources/
│   ├── ConvertAnythingApp/      # NSApplication entry point and lifecycle
│   ├── ConvertAnythingCore/     # Rules, planning, queue, processes, and settings
│   └── ConvertAnythingMac/      # AppKit/SwiftUI UI and platform adapters
├── Tests/
│   ├── ConvertAnythingCoreTests/
│   ├── ConvertAnythingIntegrationTests/
│   ├── ConvertAnythingMacTests/
│   ├── ConvertAnythingTestSupport/
│   └── Fixtures/
├── scripts/                     # Build, install, test, packaging, and smoke scripts
├── install.sh                   # Public source bootstrap installer
├── Package.swift                # Swift package products and executable test targets
└── THIRD_PARTY_NOTICES.md       # Bundled component license notices
```

Generated state is intentionally outside source control:

- `.build/` contains Swift build products.
- `build/vendor/` contains downloaded and compiled media tools plus the source offer.
- `dist/Convert Anything.app` is the assembled application.
- `~/Library/Application Support/com.channprj.convert-anything/settings.json` contains user rules.

## Design decisions

### Preserve sources and validate before publication

Outputs are siblings of the input. Name collisions advance from `sample.ext` to `sample-converted.ext`, then `sample-converted-2.ext` and higher. Encoding targets a unique hidden file; a validated result is moved into place only when the final name is still free.

### Constrain conversion instead of exposing commands

Users select a media family, target, extension set, and quality preset. Target-family compatibility and enabled extension ownership are validated, and raw FFmpeg arguments are not accepted. The process layer passes file paths as `Process.arguments`, so paths are never interpolated into a shell command.

### Serialize work with actor isolation

`ConversionQueue` is an actor and intentionally runs one conversion at a time. This keeps CPU and disk pressure predictable, gives cancellation one active process to target, and makes the queue-drain summary deterministic.

### Keep settings recoverable and migratable

`SettingsDocument` currently uses schema version 2. `MappingStore` migrates older documents, normalizes extensions, rejects incompatible or duplicate enabled mappings, and writes JSON atomically. The Settings UI remains the supported editing surface.

### Bundle a reproducible media toolchain

`scripts/build-ffmpeg.sh` downloads pinned release archives, verifies SHA-256 hashes, and builds the arm64 media tools.

Versions, download URLs, and hashes are pinned in `Dependencies/ffmpeg/versions.env`. FFmpeg is configured with GPL and nonfree components disabled and links the required libvpx, libaom, Opus, and LAME codecs without Homebrew or developer-workspace runtime dependencies.

Every built app includes `THIRD_PARTY_NOTICES.md` and the matching upstream source archives, license texts, hash manifest, and reproduction instructions under:

```text
Contents/Resources/source-offer
```

Keep that directory intact with every distributed copy. See `THIRD_PARTY_NOTICES.md` for component licenses.

### Separate local verification from trusted distribution

`scripts/build-app.sh` creates an ad-hoc signed local bundle. Developer ID signing, notarization, stapling, automatic updates, and trusted public binary distribution are not implemented.

### Use executable test targets

Core, macOS adapter, and real-media suites are Swift executable targets backed by a shared lightweight harness. `scripts/check.sh` combines those suites with formatting, release build, app assembly, signature, installer, packaging, and packaged runtime checks.
