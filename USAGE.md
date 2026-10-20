# Convert Anything Usage

## Installation

### Requirements

- Apple Silicon Mac
- macOS 14 or later
- Xcode Command Line Tools with Swift 6.2 or later
- CMake, Ninja, and pkg-config

Install the command-line prerequisites when needed:

```bash
xcode-select --install
brew install cmake ninja pkg-config
```

The application and bundled media tools are built for arm64 only.

### Install from the public source repository

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/channprj/convert-anything/main/install.sh | bash
```

The bootstrap installer validates the platform and required commands, downloads a clean repository archive, runs the pinned media-tool build, assembles the app, replaces `/Applications/Convert Anything.app`, verifies its signature, and launches it. Building FFmpeg and its codecs can take several minutes.

The installer supports two maintainer-oriented environment overrides:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONVERT_ANYTHING_REF` | `main` | Git ref requested from the GitHub archive API. |
| `CONVERT_ANYTHING_SOURCE_URL` | GitHub tarball URL for the selected ref | Alternate source archive URL. |

### Build from an existing checkout

Build the pinned media toolchain once, then assemble and launch the app:

```bash
zsh scripts/build-ffmpeg.sh
zsh scripts/build-app.sh
open "dist/Convert Anything.app"
```

The first command downloads release archives, verifies every SHA-256 hash, and builds arm64 `ffmpeg` and `ffprobe`. The second command creates and ad-hoc signs:

```text
dist/Convert Anything.app
```

When `build/vendor/ffmpeg/bin` already exists, install the current checkout into `/Applications` with:

```bash
zsh scripts/install.sh
```

The local installer builds the app, asks a running copy to quit, replaces the installed bundle, verifies it, and relaunches it.

## Quick start

1. Start **Convert Anything**. It appears only in the menu bar.
2. Drop one or more supported files directly onto the menu bar icon. You can also click the icon and drop files onto the larger popover.
3. Inspect active, queued, completed, failed, or canceled jobs in the popover.
4. Use **Cancel** for active work, **Retry** for a failed job, **Show Output** or **Show Source** to reveal files in Finder, and **Clear** to remove finished entries from the in-memory list.
5. Open **Settings…** to change enabled extensions, output targets, and quality presets.

The app processes one job at a time. Additional accepted drops join the current queue.

## Default conversion rules

| Input | Output | Smaller | Balanced | Higher Quality |
| --- | --- | --- | --- | --- |
| WAV, AIFF, FLAC, CAF | M4A/AAC | 96 kbps | 160 kbps | 256 kbps |
| M4A | MP3/LAME | 96 kbps | 160 kbps | 256 kbps |
| MOV, MP4, MKV | WebM/VP9 + Opus | CRF 38, 64 kbps | CRF 32, 96 kbps | CRF 26, 128 kbps |
| WebM | MP4/H.264 + AAC | Q 40, 64 kbps | Q 55, 96 kbps | Q 70, 128 kbps |
| JPEG, JPG, PNG, TIFF | AVIF/AV1 | CRF 38 | CRF 30 | CRF 22 |
| WebP | JPG or PNG | q 8 | q 5 | q 2 |
| HEIC | JPG or PNG | q 8 | q 5 | q 2 |

WebP and HEIC inputs choose the safe output per file: a source with alpha becomes lossless PNG so transparency survives, while an opaque source becomes JPG. MP4 video uses the hardware VideoToolbox H.264 encoder.

## Command reference

| Command | Purpose |
| --- | --- |
| `zsh scripts/build-ffmpeg.sh` | Download, verify, and build the pinned arm64 media toolchain and source offer. |
| `zsh scripts/build-app.sh` | Build the release executable, assemble `dist/Convert Anything.app`, bundle tools and notices, strip binaries, and ad-hoc sign the bundle. |
| `zsh scripts/install.sh` | Build and replace `/Applications/Convert Anything.app`, verify it, and launch it. Requires the media toolchain to exist. |
| `zsh scripts/make-appicon.sh` | Regenerate `App/AppIcon.icns` from the shared brand glyph after a glyph change. |
| `zsh scripts/check.sh` | Run the complete formatting, installer, test, build, packaging, signature, and runtime acceptance gate. |
| `swift run ConvertAnythingCoreTests` | Run the 88 core tests. |
| `swift run ConvertAnythingMacTests` | Run the 14 macOS adapter tests. |
| `zsh scripts/integration-test.sh` | Generate fixtures and run the 15 real-media integration tests with the bundled tools. |
| `zsh scripts/runtime-smoke.sh` | Launch the packaged app, perform four conversions, verify sources and output codecs, and quit normally. |
| `zsh scripts/test-packaging.sh` | Verify bundle contents, source offer, codecs, architecture, dependencies, and code signature. |
| `zsh scripts/test-install.sh` | Exercise the curl bootstrap installer against a local archive and check that CLI credentials are not forwarded. |

The packaged executable also accepts `--ingest <absolute-path>...` as an internal automated-test entry point. Normal use is drag and drop through the status item or popover.

### App icon

The app icon and menu bar item draw the same mark from `Sources/ConvertAnythingMac/StatusBar/BrandGlyph.swift`. `App/AppIcon.icns` is committed, so ordinary builds do not regenerate it.

## Configuration

### Conversion rules

Use **Settings…** to add, edit, enable, disable, or remove rules. Each rule contains:

- one media family: `audio`, `video`, or `image`;
- one or more source extensions;
- a target from the same media family;
- one quality preset: `smaller`, `balanced`, or `higherQuality`; and
- an enabled state.

Extensions are trimmed, lowercased, stripped of leading dots, and deduplicated within a rule. Every rule must retain at least one extension, and the same extension cannot belong to multiple enabled rules. Raw FFmpeg arguments are never accepted.

Use **Restore Defaults** to replace the current draft with the seven built-in rules.

### Settings storage

Settings are stored as schema-versioned JSON at:

```text
~/Library/Application Support/com.channprj.convert-anything/settings.json
```

`MappingStore` writes this file atomically and migrates supported older schemas. The current schema version is 3. Use the Settings window instead of hand-editing the JSON so validation remains intact.

Job history is not persisted across app launches.

### Notifications

Notification permission is requested after the first accepted drop. When authorized, one local summary is delivered after the queue drains. If permission is denied or unavailable, conversion continues and the same summary remains in the popover.

## Examples

### Convert several files

Drop multiple supported files together. Accepted inputs enter one serial queue; an invalid or disabled extension is reported without preventing other accepted files from being planned.

### Preserve an existing output

For `sample.wav`, the first available M4A output is selected in this order:

```text
sample.m4a
sample-converted.m4a
sample-converted-2.m4a
sample-converted-3.m4a
```

Encoding uses a unique hidden sibling temporary file. The selected final path appears only after the output has been validated, and the source remains untouched.

### Preserve WebP and HEIC transparency

Drop an alpha-bearing `image.webp` or `image.heic` to create `image.png`. Drop an opaque `photo.webp` or `photo.heic` to create `photo.jpg`. The decision is based on probed media content rather than the filename alone. Tiled HEIC photos, including iPhone pictures, are reassembled to the full clean frame and saved upright.

### Reverse a default route

Drop `clip.webm` to create an H.264/AAC `clip.mp4`, or drop `audio.m4a` to create an MP3 using LAME. Change the quality preset in **Settings…** before dropping the file when the default Balanced profile is not desired.

## Verification

After building the media toolchain, quit any installed `ConvertAnything` process and run:

```bash
zsh scripts/check.sh
```

The gate runs strict Swift formatting, the curl installer test, 88 core tests, 14 macOS adapter tests, 15 real-media integration tests, a release build, app assembly and signature checks, packaging checks, and a packaged runtime smoke test.

The runtime smoke test launches one app process, converts WAV, MOV, opaque PNG, and alpha PNG fixtures, verifies source SHA-256 values and output codecs, and quits the app normally.

The repository uses executable Swift test harnesses because the available Command Line Tools environment does not provide a usable XCTest runner for this package. A missing `CONVERT_ANYTHING_TOOL_DIR` intentionally skips only a direct invocation of the integration executable; `scripts/integration-test.sh` always supplies and verifies the bundled tools.

## Troubleshooting

- **Bundled tools are missing:** run `zsh scripts/build-ffmpeg.sh`, then `zsh scripts/build-app.sh`.
- **A file is rejected:** confirm it is a readable regular file with an enabled extension in **Settings…**. Folder recursion is not supported.
- **There is not enough disk space:** free capacity on the source volume. Preflight reserves a conservative output estimate plus a 64 MiB temporary-file margin.
- **No notification appears:** allow Convert Anything in System Settings → Notifications. Conversion results remain available in the popover when permission is denied.
- **The full check reports an existing process:** quit the installed app before running `zsh scripts/check.sh`; the runtime smoke test must prove that it launched exactly one process.
- **Settings cannot be loaded:** restore a compatible schema-version 3 settings file or move the invalid file aside and relaunch so defaults can be created.
- **The app cannot be distributed to another Mac as a trusted download:** the current bundle is locally ad-hoc signed and not notarized. Developer ID signing and public release packaging are outside this MVP.

## Current limitations

The MVP does not delete originals, recurse through folders, watch directories, provide Finder Quick Actions, accept arbitrary commands, persist conversion history, upload media, run parallel transcodes, support Intel Macs, produce animated AVIF from video, update itself, or ship through the Mac App Store.
