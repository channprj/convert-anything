# Convert Anything

Convert Anything is a small macOS menu bar app for local media conversion. Drop a supported file on its menu bar icon and it saves the converted copy next to the untouched original.

[한국어](README.ko.md)

This repository provides a source build. The app bundle is ad-hoc signed, not Developer ID signed or notarized, and not distributed as a trusted binary. Automatic updates are not included.

## Highlights

- Converts seven default routes: lossless audio to M4A, M4A to MP3, common video to WebM, WebM to MP4, common images to AVIF, WebP to JPG or PNG, and HEIC to JPG or PNG.
- Preserves every source and publishes an output only after probing, encoding to a hidden temporary file, and validating the result.
- Processes one job at a time with visible progress, cancellation, retry, Finder reveal actions, and a queue-drain summary.
- Runs locally with bundled, pinned FFmpeg tools and no account, cloud upload, analytics, telemetry, database, or runtime network feature.

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- Xcode Command Line Tools with Swift 6.2 or later
- CMake, Ninja, and pkg-config for the bundled media-tool build

The generated app is arm64-only.

## Installation

Install from source into `/Applications`:

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/channprj/convert-anything/main/install.sh | bash
```

The installer downloads a clean source archive, builds the pinned media toolchain and app, ad-hoc signs the bundle, replaces `/Applications/Convert Anything.app`, and launches it. The initial media build can take several minutes.

See [Usage](USAGE.md#installation) for prerequisites, local-checkout installation, and development commands.

## Quick start

1. Launch **Convert Anything**. It appears only in the menu bar.
2. Drop one or more supported files onto the menu bar icon, or click the icon and drop them into the popover.
3. Follow progress in the popover. Use **Cancel**, **Retry**, **Show Output**, **Show Source**, or **Clear** as needed.

Open **Settings…** to enable, edit, add, or remove conversion rules and choose a quality preset.

## More documentation

- [Usage](USAGE.md) - installation, default rules, commands, configuration, examples, verification, and troubleshooting
- [Architecture](ARCHITECTURE.md) - components, data flow, directory structure, and design decisions
- [Third-Party Notices](THIRD_PARTY_NOTICES.md) - bundled media component licenses

## Privacy

The app performs media inspection and conversion locally. It has no account, cloud upload, analytics, telemetry, database, or runtime network feature. File paths are passed directly to `Process` as argument arrays and never interpolated into a shell command. The build script uses the network only to download the pinned upstream source archives.

## License

No project-level `LICENSE` file is currently included. Bundled third-party components retain their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
