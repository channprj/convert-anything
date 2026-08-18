# Convert Anything

Convert Anything is a native, Dock-less macOS menu bar utility for predictable local media conversion. Drop supported files onto its status item or popover and it writes efficient copies beside the untouched originals.

This repository currently ships a local MVP build. It is not Developer ID signed, notarized, distributed publicly, or configured for automatic updates.

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- Xcode Command Line Tools with Swift 6.2 or later
- CMake, Ninja, and pkg-config to build the bundled media tools

The generated app is arm64-only.

## Default Rules

| Input | Output | Smaller | Balanced | Higher Quality |
| --- | --- | --- | --- | --- |
| WAV, AIFF, FLAC, CAF | M4A/AAC | 96 kbps | 160 kbps | 256 kbps |
| MOV, MP4, MKV | WebM/VP9 + Opus | CRF 38, 64 kbps | CRF 32, 96 kbps | CRF 26, 128 kbps |
| JPEG, JPG, PNG, WebP, TIFF | AVIF/AV1 | CRF 38 | CRF 30 | CRF 22 |

Settings can add, edit, disable, or remove rules within these supported family-to-target combinations. Raw FFmpeg arguments are never accepted.

## Build and Run

Build the pinned LGPL-compatible FFmpeg toolchain once, then assemble the app:

```bash
zsh scripts/build-ffmpeg.sh
zsh scripts/build-app.sh
open "dist/Convert Anything.app"
```

The first command downloads release archives, verifies every SHA-256 value, and builds arm64 `ffmpeg` and `ffprobe`. The second command creates and ad-hoc signs:

```text
dist/Convert Anything.app
```

## Use

1. Start the app. It appears only in the menu bar.
2. Drop one or more supported files directly onto the menu bar icon. You can also click the icon and drop files onto the larger popover.
3. Click the icon to inspect active, queued, completed, failed, or canceled jobs. Active work can be canceled; failed jobs can be retried.
4. Use `Show Output` or `Show Source` to reveal a file in Finder.
5. Open `Settings…` to change enabled extensions or quality presets.

The app processes one job at a time. Additional drops join the current queue.

### Output Safety

Outputs are written in the source directory. The first available name is selected in this order:

```text
sample.m4a
sample-converted.m4a
sample-converted-2.m4a
sample-converted-3.m4a
```

Encoding uses a unique hidden sibling temporary file. The final path appears only after the output is non-empty and its container, codec, dimensions, orientation, and alpha contract have been validated. Source files are never renamed, replaced, modified, or deleted.

### Settings and Notifications

Settings are stored atomically as versioned JSON at:

```text
~/Library/Application Support/com.channprj.convert-anything/settings.json
```

Notification permission is requested after the first accepted drop. When authorized, one local summary is delivered after the queue drains. If permission is denied or unavailable, conversion continues and the same summary remains in the popover.

## Verification

After building the media toolchain, run the complete acceptance gate:

```bash
zsh scripts/check.sh
```

It runs Swift formatting checks, 56 core tests, 4 macOS adapter tests, 6 real-media integration tests, a release build, app assembly and signature checks, and a packaged runtime smoke test. The runtime test launches one app process, converts WAV, MOV, opaque PNG, and alpha PNG fixtures, verifies source SHA-256 values and output codecs, and quits the app normally.

Individual gates are also available:

```bash
swift run ConvertAnythingCoreTests
swift run ConvertAnythingMacTests
zsh scripts/integration-test.sh
zsh scripts/runtime-smoke.sh
zsh scripts/test-packaging.sh
```

The repository uses executable Swift test harnesses because the available Command Line Tools environment does not provide a usable XCTest runner for this package. A missing `CONVERT_ANYTHING_TOOL_DIR` intentionally skips only a direct invocation of the integration executable; `scripts/integration-test.sh` always supplies and verifies the bundled tools.

## Media Toolchain and Licenses

Versions, download URLs, and hashes are pinned in `Dependencies/ffmpeg/versions.env`. FFmpeg is configured with GPL and nonfree components disabled and links the required libvpx, libaom, and Opus codecs without Homebrew or developer-workspace runtime dependencies.

Every built app includes `THIRD_PARTY_NOTICES.md` and the matching upstream source archives, license texts, hash manifest, and reproduction instructions under:

```text
Contents/Resources/source-offer
```

Keep that directory intact with every distributed copy. See `THIRD_PARTY_NOTICES.md` for component licenses.

## Privacy

The app performs media inspection and conversion locally. It has no account, cloud upload, analytics, telemetry, database, or runtime network feature. File paths are passed directly to `Process` as argument arrays and never interpolated into a shell command. The build script uses the network only to download the pinned upstream source archives.

## Troubleshooting

- **Bundled tools are missing:** run `zsh scripts/build-ffmpeg.sh`, then `zsh scripts/build-app.sh`.
- **A file is rejected:** confirm it is a readable regular file with an enabled extension in Settings. Folder recursion is not supported.
- **There is not enough disk space:** free capacity on the source volume. Preflight reserves a conservative output estimate plus a 64 MiB temporary-file margin.
- **No notification appears:** allow Convert Anything in System Settings → Notifications. Conversion results remain available in the popover when permission is denied.
- **The app cannot be distributed to another Mac as a trusted download:** the current bundle is locally ad-hoc signed and not notarized. Developer ID signing and public release packaging are outside this MVP.

## MVP Exclusions

The MVP does not delete originals, recurse through folders, watch directories, provide Finder Quick Actions, accept arbitrary commands, persist conversion history, upload media, run parallel transcodes, support Intel Macs, produce animated AVIF from video, update itself, or ship through the Mac App Store.
