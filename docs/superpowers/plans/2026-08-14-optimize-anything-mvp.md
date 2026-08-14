# Optimize Anything MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a native Apple Silicon macOS menu bar app that converts dropped media through configurable safe presets, writes outputs beside untouched originals, and posts one native completion notification when its serial queue drains.

**Architecture:** A Foundation-only `OptimizeAnythingCore` library owns rules, settings, admission, planning, subprocess execution, validation, and the serial queue. An AppKit/SwiftUI `OptimizeAnythingMac` library owns the menu bar drop surface, popover, settings window, Finder actions, and `UNUserNotificationCenter`; a thin executable target starts it. Pinned LGPL-compatible FFmpeg and FFprobe executables are built reproducibly and embedded in an ad-hoc-signed `.app` bundle.

**Tech Stack:** Swift 6.3, Swift Package Manager, AppKit, SwiftUI, Foundation `Process`, UserNotifications, executable Swift test harnesses, FFmpeg 8.0, libvpx 1.15.0, libaom 3.12.1, Opus 1.5.2, zsh build and acceptance scripts.

## Global Constraints

- Target Apple Silicon and macOS 14 or later; Intel and universal builds are outside the MVP.
- Run as an accessory application with `LSUIElement=true`; do not create a Dock item or a normal main window.
- Preserve every source byte. Never rename, replace, mutate, or delete an input.
- Write to a unique hidden sibling temporary file and expose a final output only after a successful non-empty output validation.
- Use the first free name in this order: `<stem>.<target>`, `<stem>-optimized.<target>`, `<stem>-optimized-2.<target>`, then increasing suffixes.
- Run exactly one conversion process at a time and coalesce UI progress to at most ten updates per second.
- Default balanced rules are WAV/AIFF/FLAC/CAF to M4A AAC-LC 160 kbps, MOV/MP4/MKV to WebM VP9 CRF 32 plus Opus 96 kbps, and JPEG/PNG/WebP/TIFF to AVIF AV1 CRF 30.
- Expose only compatible targets and the exact `Smaller`, `Balanced`, and `Higher Quality` presets; never accept raw FFmpeg arguments.
- Store settings as an atomically written schema-versioned JSON document. Migrations are one-time and field-by-field and do not overwrite an intentional later user choice.
- Invoke FFmpeg and FFprobe with an executable URL and argument array; never route a user path through a shell.
- Keep all media and path data local. Do not add network features, accounts, telemetry, analytics, or persistent job history.
- Bundle tools built without `--enable-gpl` and without `--enable-nonfree`; include exact source metadata and third-party notices.
- Request local notification permission only on the first accepted drop. Denial cannot block conversion and must retain the same summary in the popover.
- Additional drops while work is active join the current queue-drain summary so the app posts one notification rather than one per file.
- Use TDD for deterministic core behavior. A checkpoint is eligible to commit only after its narrow tests, all accumulated tests, and `git diff --check` pass.
- Under `$gcpr`, stage explicit paths, use the stated Conventional Commit, push immediately, and prove `HEAD...@{u}` is `0 0` before starting the next task.

---

## File and Responsibility Map

```text
Package.swift
Sources/
  OptimizeAnythingCore/
    Model/
      MediaTypes.swift             # media families, targets, quality presets
      ConversionRule.swift         # rules, settings document, validation errors
      ConversionJob.swift          # immutable plans, mutable-state values, outcomes
    Settings/
      RuleCatalog.swift            # built-in rules and compatibility matrix
      MappingStore.swift           # JSON load/save/migration
    Planning/
      DropAdmissionService.swift   # per-URL validation and rule matching
      OutputPathResolver.swift     # final/temp sibling names
      ConversionPlanner.swift      # immutable job plans and capacity preflight
      EncoderArguments.swift       # explicit FFmpeg arguments for nine profiles
    Process/
      CommandExecutor.swift        # subprocess protocol and Foundation adapter
      FFprobeClient.swift          # media JSON probe and output postconditions
      FFmpegRunner.swift           # progress parsing and cancellation
      ConversionService.swift      # probe -> encode -> validate -> atomic finalize
    Queue/
      ConversionQueue.swift        # serial ownership and drain boundary
      DrainSummary.swift           # counts, savings, and last output
  OptimizeAnythingMac/
    AppViewModel.swift             # MainActor bridge from queue/settings to views
    ApplicationController.swift    # lifecycle and dependency graph
    StatusBar/
      StatusBarController.swift    # NSStatusItem and popover state
      StatusBarDropView.swift      # NSDraggingDestination overlay and pasteboard URLs
    Views/
      PopoverView.swift            # active, queued, and current-session results
      JobRowView.swift             # progress and terminal actions
      SettingsView.swift           # constrained rule editor
      SettingsWindowController.swift
    Notifications/
      LocalNotificationService.swift
    FinderService.swift
  OptimizeAnythingApp/
    main.swift
    AppDelegate.swift
Tests/
  OptimizeAnythingCoreTests/
    TestSupport.swift               # temp files, hashes, async assertions, fixtures
                                    # plus deterministic unit tests
  OptimizeAnythingMacTests/
    MacTestSupport.swift            # fake queue, notification, Finder, and planner
                                    # plus pasteboard and view-model tests
  OptimizeAnythingIntegrationTests/# real media and bundled tool tests
App/Info.plist
Dependencies/ffmpeg/versions.env
scripts/
  build-ffmpeg.sh
  build-app.sh
  generate-fixtures.sh
  integration-test.sh
  runtime-smoke.sh
  check.sh
THIRD_PARTY_NOTICES.md
README.md
.gitignore
```

The task sequence below is also the realtime checkpoint sequence:

| Task | Commit | Independently reviewable outcome |
| --- | --- | --- |
| 1 | `feat(settings): add validated conversion rule storage` | Defaults and intentional settings survive relaunch and migration |
| 2 | `feat(planning): add safe media conversion plans` | Drops map to collision-safe paths and exact codec arguments |
| 3 | `feat(conversion): run and validate local media conversions` | A plan executes transactionally through injectable subprocesses |
| 4 | `feat(queue): orchestrate serial conversion batches` | Jobs progress serially and emit one deterministic drain summary |
| 5 | `feat(macos): add menu bar drop and settings experience` | The native app accepts drops and exposes queue/settings actions |
| 6 | `build(macos): package reproducible media toolchain` | An ad-hoc-signed app embeds verified LGPL-compatible tools |
| 7 | `test(integration): verify real media optimization flows` | Real WAV, MOV, opaque PNG, and alpha PNG contracts pass |
| 8 | `docs: document local optimization workflow` | Usage, build, privacy, and limitations match shipped behavior |

### Shared Test Support Contract

`Tests/OptimizeAnythingCoreTests/TestSupport.swift` is created in Task 1 with
temporary-file and async assertion helpers, expanded in Task 2 after planning
types exist, and expanded again in Task 3 after probe/outcome types exist.

The available Command Line Tools installation discovered no usable XCTest tests,
so the implemented package uses executable targets named
`OptimizeAnythingCoreTests`, `OptimizeAnythingMacTests`, and
`OptimizeAnythingIntegrationTests`. Each harness runs named async `TestCase`
values, prints exact pass/fail totals, and exits nonzero on any failure. This is
the authoritative test path used by `scripts/check.sh`.

Task-local fakes are defined in their named test file, not hidden in production
code. Each fake records every call, exposes bounded async wait methods through
`eventually`, and finishes every suspended continuation so a failed test cannot
hang the suite.

### Task 1: Validated Rules and Versioned Settings

**Files:**
- Create: `Package.swift`
- Create: `Sources/OptimizeAnythingCore/Model/MediaTypes.swift`
- Create: `Sources/OptimizeAnythingCore/Model/ConversionRule.swift`
- Create: `Sources/OptimizeAnythingCore/Settings/RuleCatalog.swift`
- Create: `Sources/OptimizeAnythingCore/Settings/MappingStore.swift`
- Create: `Tests/OptimizeAnythingCoreTests/TestSupport.swift`
- Create: `Tests/OptimizeAnythingCoreTests/RuleCatalogTests.swift`
- Create: `Tests/OptimizeAnythingCoreTests/MappingStoreTests.swift`

**Interfaces:**
- Consumes: Approved profile values and the one-enabled-rule-per-extension invariant from the PRD.
- Produces: `MediaFamily`, `TargetFormat`, `QualityPreset`, `ConversionRule`, `SettingsDocument`, `RuleCatalog`, `RuleValidator.validate(_:)`, and actor `MappingStore.load()/save(_:)` for every later task.

- [x] **Step 1: Create the package manifest and failing rule tests**

Start with only source-bearing core targets. Task 5 extends this manifest when
Mac sources are created, and Task 7 adds the integration target when its test
source is created:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OptimizeAnything",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OptimizeAnythingCore", targets: ["OptimizeAnythingCore"]),
    ],
    targets: [
        .target(name: "OptimizeAnythingCore"),
        .executableTarget(
            name: "OptimizeAnythingCoreTests",
            dependencies: ["OptimizeAnythingCore"],
            path: "Tests/OptimizeAnythingCoreTests"
        ),
    ]
)
```

Start `RuleCatalogTests` with named cases covering the three exact default
arrays and targets, leading-dot and case normalization,
enabled-rule conflicts, disabled-rule coexistence, empty sources, incompatible
targets, and the family compatibility matrix. Each is a named async `TestCase`
using the shared `expectEqual`, `expectTrue`, or `expectThrows` helper.

- [x] **Step 2: Run the rule tests and observe the missing-type failure**

Run: `swift run OptimizeAnythingCoreTests`

Expected: compilation fails because `RuleCatalog`, `ConversionRule`, and related enums do not exist.

- [x] **Step 3: Implement the value types, catalog, and validator**

Use lowercase serialized raw values, deterministic rule IDs, normalized extensions without a leading dot, and localized display labels only in the Mac target:

```swift
public enum MediaFamily: String, Codable, CaseIterable, Sendable {
    case audio, video, image
}

public enum TargetFormat: String, Codable, CaseIterable, Sendable {
    case m4a, webm, avif

    public var family: MediaFamily {
        switch self {
        case .m4a: .audio
        case .webm: .video
        case .avif: .image
        }
    }
}

public enum QualityPreset: String, Codable, CaseIterable, Sendable {
    case smaller, balanced, higherQuality
}

public struct ConversionRule: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var family: MediaFamily
    public var sourceExtensions: [String]
    public var target: TargetFormat
    public var quality: QualityPreset
    public var isEnabled: Bool
}

public struct SettingsDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var rules: [ConversionRule]
}
```

`RuleValidator.validate(_:)` must normalize a copy, reject an empty source list, reject a target whose family differs, and reject duplicate extensions only among enabled rules. `RuleCatalog.defaultRules` must use stable UUIDs ending in `1`, `2`, and `3` so migrations can identify built-in rules without comparing mutable fields.

Expose those IDs as `RuleCatalog.audioRuleID`, `videoRuleID`, and
`imageRuleID`. Define `RuleValidationError: Error, Equatable, Sendable` with
`emptySourceExtensions(ruleID:)`, `incompatibleTarget(ruleID:)`,
`duplicateSourceExtension(_:)`, and `unsupportedSchemaVersion(_:)`. The
validator signature is `public static func validate(_ rules:
[ConversionRule]) throws -> [ConversionRule]`; callers persist and use the
returned normalized copy.

- [x] **Step 4: Run the rule tests and confirm they pass**

Run: `swift run OptimizeAnythingCoreTests`

Expected: all `RuleCatalogTests` pass.

- [x] **Step 5: Add failing atomic persistence and migration tests**

Use a unique temporary directory per test and cover the missing-file default
write, saved intentional quality choice, invalid-save
byte preservation, schema-zero one-time migration, future-schema rejection, and
normalized persistence cases.

- [x] **Step 6: Run persistence tests and observe the missing-store failure**

Run: `swift run OptimizeAnythingCoreTests`

Expected: compilation fails because `MappingStore` does not exist.

- [x] **Step 7: Implement the actor-backed JSON store**

`MappingStore.load()` must create its parent directory, decode when the file exists, reject schema versions greater than one, apply `migrate(_:)`, validate rules, and write defaults once when missing. `save(_:)` validates before encoding with `.prettyPrinted` and `.sortedKeys`, writes with `.atomic`, and never mutates the existing file after a validation failure.

```swift
public actor MappingStore {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> SettingsDocument
    public func save(_ document: SettingsDocument) throws
    static func migrate(_ document: SettingsDocument) throws -> SettingsDocument
}
```

Define the consumer boundary beside it and make `MappingStore` conform:

```swift
public protocol SettingsServing: Sendable {
    func load() async throws -> SettingsDocument
    func save(_ document: SettingsDocument) async throws
}
```

No migration rewrites a known rule field merely because a newer app default differs. A future migration may append a missing stable built-in rule and increment the schema exactly once.

- [x] **Step 8: Run Task 1 gates**

Run:

```bash
swift run OptimizeAnythingCoreTests
swift build
git diff --check
```

Expected: tests and build pass with no diff errors.

- [x] **Step 9: Commit and push Task 1**

Stage only the Task 1 source, tests, and manifest. Commit `feat(settings): add validated conversion rule storage`, push, then require `git rev-list --left-right --count HEAD...@{u}` to print `0 0`.

### Task 2: Admission, Output Paths, Planning, and Encoder Profiles

**Files:**
- Create: `Sources/OptimizeAnythingCore/Model/ConversionJob.swift`
- Create: `Sources/OptimizeAnythingCore/Planning/DropAdmissionService.swift`
- Create: `Sources/OptimizeAnythingCore/Planning/OutputPathResolver.swift`
- Create: `Sources/OptimizeAnythingCore/Planning/ConversionPlanner.swift`
- Create: `Sources/OptimizeAnythingCore/Planning/EncoderArguments.swift`
- Create: `Tests/OptimizeAnythingCoreTests/DropAdmissionServiceTests.swift`
- Create: `Tests/OptimizeAnythingCoreTests/OutputPathResolverTests.swift`
- Create: `Tests/OptimizeAnythingCoreTests/EncoderArgumentsTests.swift`
- Modify: `Tests/OptimizeAnythingCoreTests/TestSupport.swift`

**Interfaces:**
- Consumes: `ConversionRule`, `RuleValidator`, `TargetFormat`, and `QualityPreset` from Task 1.
- Produces: `AdmissionDecision`, `OutputPaths`, `ConversionPlan`, `InputMediaInfo`, `EncoderArguments.make(plan:media:)`, and `ConversionPlanner.plan(input:rule:jobID:)` for Tasks 3–5.

- [x] **Step 1: Write failing admission and path tests**

Cover mixed supported/unsupported input, uppercase extension normalization, directories, unreadable files, source preservation, and collision order:

```swift
func testAdmissionReturnsPerPathResultsWithoutAbortingBatch() throws {
    let wav = try fixtureFile(named: "VOICE.WAV", bytes: Data([1]))
    let txt = try fixtureFile(named: "notes.txt", bytes: Data([2]))
    let decisions = DropAdmissionService().admit(
        [wav, txt],
        rules: RuleCatalog.defaultRules
    )
    XCTAssertEqual(decisions.map(\.status), [
        .accepted(ruleID: RuleCatalog.audioRuleID),
        .rejected(.unsupportedExtension("txt")),
    ])
}

func testOutputNamesFollowCollisionContract() throws {
    let source = try fixtureFile(named: "sample.wav", bytes: Data([1]))
    try Data([9]).write(to: source.deletingPathExtension().appendingPathExtension("m4a"))
    try Data([8]).write(to: source.deletingLastPathComponent().appending(path: "sample-optimized.m4a"))
    let paths = try OutputPathResolver().resolve(
        input: source,
        target: .m4a,
        jobID: UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
    )
    XCTAssertEqual(paths.final.lastPathComponent, "sample-optimized-2.m4a")
    XCTAssertTrue(paths.temporary.lastPathComponent.hasPrefix(".sample.optimize-anything-"))
    XCTAssertEqual(try Data(contentsOf: source), Data([1]))
}
```

- [x] **Step 2: Run the focused tests and confirm missing-symbol failures**

Run: `swift run OptimizeAnythingCoreTests`

Expected: compilation fails because the planning types do not exist.

- [x] **Step 3: Implement admission, plan, and path models**

Use these exact public shapes:

```swift
public struct AdmissionDecision: Equatable, Sendable {
    public let input: URL
    public let status: AdmissionStatus
}

public enum AdmissionError: Error, Equatable, Sendable {
    case missingFile
    case notRegularFile
    case unreadableFile
    case missingExtension
    case unsupportedExtension(String)
}

public enum AdmissionStatus: Equatable, Sendable {
    case accepted(ruleID: UUID)
    case rejected(AdmissionError)
}

public struct OutputPaths: Equatable, Sendable {
    public let final: URL
    public let temporary: URL
}

public struct ConversionPlan: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let input: URL
    public let output: OutputPaths
    public let rule: ConversionRule
    public let sourceByteCount: Int64
}

public struct InputMediaInfo: Equatable, Sendable {
    public let containerNames: [String]
    public let durationSeconds: Double?
    public let videoCodec: String?
    public let audioCodec: String?
    public let width: Int?
    public let height: Int?
    public let channelCount: Int?
    public let hasAlpha: Bool
    public let rotationDegrees: Int?
}

public enum PlanningError: Error, Equatable, Sendable {
    case inputUnavailable
    case insufficientDiskSpace(required: Int64, available: Int64)
    case noEnabledRule(String)
}

public protocol DropAdmitting: Sendable {
    func admit(_ urls: [URL], rules: [ConversionRule]) async -> [AdmissionDecision]
}

public protocol ConversionPlanning: Sendable {
    func plan(input: URL, rule: ConversionRule, jobID: UUID) async throws -> ConversionPlan
}

public struct DropAdmissionService: DropAdmitting {
    public func admit(_ urls: [URL], rules: [ConversionRule]) async -> [AdmissionDecision]
}

public struct OutputPathResolver: Sendable {
    public func resolve(input: URL, target: TargetFormat, jobID: UUID) throws -> OutputPaths
}

public struct ConversionPlanner: ConversionPlanning {
    public func plan(input: URL, rule: ConversionRule, jobID: UUID) async throws -> ConversionPlan
}

public enum EncoderArguments {
    public static func make(plan: ConversionPlan, media: InputMediaInfo) -> [String]
}
```

Extend `TestSupport.swift` with `makePlan(source:target:quality:)` that creates a
real source file in a new temporary directory, resolves its output paths with a
stable job UUID, and returns a `ConversionPlan`. Also add exact media fixtures:
`audioFixture` has two channels and no video, `videoWithAudioFixture` is
320×180 with VP9-placeholder video metadata, and `alphaImageFixture` is 96×64
with `hasAlpha=true`. These fixtures initialize every `InputMediaInfo` field,
including `containerNames`, so later additions fail to compile instead of
silently taking a default.

`DropAdmissionService` resolves symlinks, accepts only regular readable files, and performs one deterministic first-match lookup among validated enabled rules. `OutputPathResolver` checks candidate existence in the source directory and always uses a UUID-bearing hidden temporary sibling. `ConversionPlanner` reads allocated size, obtains volume important-usage capacity, and throws `.insufficientDiskSpace` when the conservative family multiplier plus 64 MiB margin cannot fit.

- [x] **Step 4: Run admission and path tests to green**

Run: `swift run OptimizeAnythingCoreTests`

Expected: all focused tests pass.

- [x] **Step 5: Write failing argument tests for all nine profiles**

Table-drive every family and quality. Assert complete arrays so an accidental FFmpeg default cannot silently change the product contract. Representative balanced assertions:

```swift
func testBalancedAudioArgumentsAreExplicitAndShellFree() throws {
    let plan = makePlan(source: "voice with $dollars.wav", target: .m4a, quality: .balanced)
    XCTAssertEqual(EncoderArguments.make(plan: plan, media: .audioFixture), [
        "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
        "-i", plan.input.path,
        "-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "160k",
        "-progress", "pipe:1", plan.output.temporary.path,
    ])
}

func testBalancedVideoArgumentsUseVP9AndOptionalOpus() throws {
    let plan = makePlan(source: "movie.mov", target: .webm, quality: .balanced)
    let arguments = EncoderArguments.make(plan: plan, media: .videoWithAudioFixture)
    XCTAssertContainsSubsequence(arguments, ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1"])
    XCTAssertContainsSubsequence(arguments, ["-map", "0:a:0?", "-c:a", "libopus", "-b:a", "96k"])
}

func testAlphaAVIFUsesColorAndAuxiliaryAlphaStreams() throws {
    let plan = makePlan(source: "overlay.png", target: .avif, quality: .balanced)
    let arguments = EncoderArguments.make(plan: plan, media: .alphaImageFixture)
    XCTAssertContainsSubsequence(arguments, [
        "-filter_complex", "[0:v:0]split=2[color][alpha];[alpha]alphaextract[alphaout]",
        "-map", "[color]", "-map", "[alphaout]",
    ])
    XCTAssertContainsSubsequence(arguments, ["-c:v", "libaom-av1", "-crf", "30", "-still-picture", "1"])
}
```

- [x] **Step 6: Run argument tests and observe the missing-builder failure**

Run: `swift run OptimizeAnythingCoreTests`

Expected: compilation fails because `EncoderArguments` does not exist.

- [x] **Step 7: Implement explicit profile argument construction**

Map qualities exactly:

```swift
private static let audioBitrate: [QualityPreset: String] = [
    .smaller: "96k", .balanced: "160k", .higherQuality: "256k",
]
private static let videoCRF: [QualityPreset: String] = [
    .smaller: "38", .balanced: "32", .higherQuality: "26",
]
private static let videoAudioBitrate: [QualityPreset: String] = [
    .smaller: "64k", .balanced: "96k", .higherQuality: "128k",
]
private static let imageCRF: [QualityPreset: String] = [
    .smaller: "38", .balanced: "30", .higherQuality: "22",
]
```

Every command starts with `-nostdin -hide_banner -loglevel error -n`, includes `-progress pipe:1`, maps only the primary relevant streams, and ends with the temporary output path. Do not add `-y`. For alpha AVIF, encode the color and extracted grayscale alpha as two AV1 streams; for opaque input, map only the primary video stream.

- [x] **Step 8: Run Task 2 gates**

Run:

```bash
swift run OptimizeAnythingCoreTests
swift build
git diff --check
```

Expected: all accumulated tests and the build pass.

- [x] **Step 9: Commit and push Task 2**

Stage only Task 2 paths. Commit `feat(planning): add safe media conversion plans`, push, and prove `0 0` upstream parity.

### Task 3: Subprocesses and Transactional Conversion

**Files:**
- Create: `Sources/OptimizeAnythingCore/Process/CommandExecutor.swift`
- Create: `Sources/OptimizeAnythingCore/Process/FFprobeClient.swift`
- Create: `Sources/OptimizeAnythingCore/Process/FFmpegRunner.swift`
- Create: `Sources/OptimizeAnythingCore/Process/ConversionService.swift`
- Create: `Tests/OptimizeAnythingCoreTests/FFprobeClientTests.swift`
- Create: `Tests/OptimizeAnythingCoreTests/FFmpegRunnerTests.swift`
- Create: `Tests/OptimizeAnythingCoreTests/ConversionServiceTests.swift`
- Modify: `Tests/OptimizeAnythingCoreTests/TestSupport.swift`

**Interfaces:**
- Consumes: `ConversionPlan`, `InputMediaInfo`, `EncoderArguments`, and `OutputPaths` from Task 2.
- Produces: `CommandExecuting`, `FoundationCommandExecutor`, `FFprobeClient`, `FFmpegRunner`, `ConversionServicing`, `ConversionService.convert(_:progress:)`, and `ConversionOutcome` for the queue.

`ConversionOutcome` and its failure values are fixed before queue work begins:

```swift
public enum ConversionFailureCategory: String, Equatable, Sendable {
    case inputUnavailable
    case insufficientDiskSpace
    case invalidMedia
    case encoderUnavailable
    case encoderFailed
    case invalidOutput
    case finalizationFailed
}

public struct ConversionFailure: Error, Equatable, Sendable {
    public let category: ConversionFailureCategory
    public let message: String
}

public enum ConversionOutcome: Equatable, Sendable {
    case succeeded(output: URL, outputByteCount: Int64)
    case failed(ConversionFailure)
    case canceled

    public var failureCategory: ConversionFailureCategory? {
        guard case let .failed(failure) = self else { return nil }
        return failure.category
    }
}
```

`TestSupport.swift` adds named `InputMediaInfo` fixtures `aacM4A`,
`vp9OpusWebM`, `opaqueAVIF`, and `alphaAVIF`. `FakeCommandExecutor` is an actor
defined in `ConversionServiceTests.swift` with this exact script contract:

```swift
actor FakeCommandExecutor: CommandExecuting {
    typealias Script = @Sendable (CommandRequest) async throws -> CommandResult
    private let script: Script
    private(set) var requests: [CommandRequest] = []
    private(set) var terminatedIDs: [UUID] = []

    init(script: @escaping Script) { self.script = script }
    func execute(_ request: CommandRequest, onStandardOutputLine: @escaping @Sendable (String) -> Void) async throws -> CommandResult
    func terminate(commandID: UUID) async
}
```

The test file provides static factories `probeJSON(_:)`, `failure(status:stderr:)`,
and `successfullyWriting(_:to:postProbe:)`. Each factory returns a fully scripted
executor response sequence; no test depends on command order without asserting
the executable's last path component.

The same test file defines `makeService(executor:)` with fixed executable URLs
`/tools/ffmpeg` and `/tools/ffprobe`, a real `FileManager`, and no machine tool
lookup. This is the only `makeService` helper referenced below.

- [x] **Step 1: Write failing probe and progress parser tests**

Inject a fake executor so parsing tests never require a developer-installed binary:

```swift
func testProbeMapsJSONToMediaInfo() async throws {
    let executor = FakeCommandExecutor.probeJSON(#"{
      "format":{"duration":"2.5"},
      "streams":[
        {"codec_type":"video","codec_name":"png","pix_fmt":"rgba","width":320,"height":200},
        {"codec_type":"audio","codec_name":"pcm_s16le","channels":2}
      ]
    }"#)
    let info = try await FFprobeClient(executable: URL(fileURLWithPath: "/tools/ffprobe"), executor: executor)
        .probe(URL(fileURLWithPath: "/tmp/image.png"), commandID: UUID())
    XCTAssertEqual(info.durationSeconds, 2.5)
    XCTAssertEqual(info.width, 320)
    XCTAssertEqual(info.height, 200)
    XCTAssertEqual(info.channelCount, 2)
    XCTAssertTrue(info.hasAlpha)
}

func testProgressParserClampsOutTimeToDuration() {
    var parser = FFmpegProgressParser(durationSeconds: 2)
    XCTAssertNil(parser.consume("out_time_us=1000000"))
    XCTAssertEqual(parser.consume("progress=continue"), 0.5)
    XCTAssertNil(parser.consume("out_time_us=9000000"))
    XCTAssertEqual(parser.consume("progress=end"), 1.0)
}
```

- [x] **Step 2: Run focused parser tests and observe missing types**

Run: `swift run OptimizeAnythingCoreTests`

Expected: compilation fails because command and parser types do not exist.

- [x] **Step 3: Implement the command boundary and probe parser**

Use immutable request/result values and an actor to own live `Process` instances:

```swift
public struct CommandRequest: Sendable {
    public let id: UUID
    public let executable: URL
    public let arguments: [String]
}

public struct CommandResult: Equatable, Sendable {
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data
}

public protocol CommandExecuting: Sendable {
    func execute(
        _ request: CommandRequest,
        onStandardOutputLine: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult
    func terminate(commandID: UUID) async
}

public struct FFprobeClient: Sendable {
    public init(executable: URL, executor: any CommandExecuting)
    public func probe(_ input: URL, commandID: UUID) async throws -> InputMediaInfo
}

public struct FFmpegRunner: Sendable {
    public init(executable: URL, executor: any CommandExecuting)
    public func run(
        plan: ConversionPlan,
        media: InputMediaInfo,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CommandResult
    public func cancel(jobID: UUID) async
}
```

`FoundationCommandExecutor` must set `executableURL` and `arguments`, use pipes, drain both output streams without deadlock, resume its continuation once from `terminationHandler`, and remove the process from its actor dictionary on every exit. `terminate(commandID:)` calls `terminate()` only for a running child. It never constructs a shell command.

`FFprobeClient` uses `-v error -show_format -show_streams -of json <path>`, rejects a nonzero status, and decodes only needed fields. Alpha detection recognizes `rgba`, `bgra`, `argb`, `abgr`, any pixel format containing `yuva`, and a second AVIF auxiliary video stream.

- [x] **Step 4: Run parser tests to green**

Run: `swift run OptimizeAnythingCoreTests`

Expected: all focused tests pass.

- [x] **Step 5: Write failing transactional conversion tests**

Cover success, nonzero exit, zero-byte output, mismatched postcondition, cancel, and final-name race. The success fake writes bytes to the temporary path and returns an FFprobe result matching the target:

```swift
func testSuccessAtomicallyFinalizesAndLeavesSourceUntouched() async throws {
    let source = try fixtureFile(named: "voice.wav", bytes: Data([1, 2, 3]))
    let sourceHash = try sha256(source)
    let plan = try makePlan(for: source, target: .m4a)
    let executor = FakeCommandExecutor.successfullyWriting(
        Data([4, 5]),
        to: plan.output.temporary,
        postProbe: .aacM4A
    )
    let service = makeService(executor: executor)
    let outcome = await service.convert(plan) { _ in }
    XCTAssertEqual(outcome, .succeeded(output: plan.output.final, outputByteCount: 2))
    XCTAssertEqual(try sha256(source), sourceHash)
    XCTAssertFalse(FileManager.default.fileExists(atPath: plan.output.temporary.path))
    XCTAssertEqual(try Data(contentsOf: plan.output.final), Data([4, 5]))
}

func testNonzeroExitRemovesTemporaryAndDoesNotFinalize() async throws {
    let plan = try makePlan(for: fixtureFile(named: "bad.mov", bytes: Data([1])), target: .webm)
    let service = makeService(executor: FakeCommandExecutor.failure(status: 1, stderr: "Invalid data found"))
    let outcome = await service.convert(plan) { _ in }
    XCTAssertEqual(outcome.failureCategory, .invalidMedia)
    XCTAssertFalse(FileManager.default.fileExists(atPath: plan.output.temporary.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: plan.output.final.path))
}
```

- [x] **Step 6: Run conversion tests and observe the missing-service failure**

Run: `swift run OptimizeAnythingCoreTests`

Expected: compilation fails because `ConversionService` and `ConversionOutcome` do not exist.

- [x] **Step 7: Implement conversion as one cleanup-safe transaction**

The service owns these dependencies and phases:

```swift
public protocol ConversionServicing: Sendable {
    func convert(
        _ plan: ConversionPlan,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> ConversionOutcome
    func cancel(jobID: UUID) async
}

public final class ConversionService: ConversionServicing, @unchecked Sendable {
    public init(probe: FFprobeClient, runner: FFmpegRunner, fileManager: FileManager = .default)
    public func convert(_ plan: ConversionPlan, progress: @escaping @Sendable (Double) -> Void) async -> ConversionOutcome
    public func cancel(jobID: UUID) async
}
```

Execution order is input probe, argument construction, FFmpeg run, nonzero/cancel classification, non-empty check, target container/codec probe, collision recheck, move without replacement, and success. A `defer` removes the temporary path unless ownership has moved to the final path. Error text stores only the final relevant stderr line and a structured category; logs use the file name rather than its parent path.

Postconditions are AAC audio in an M4A-family container, VP9 video plus Opus when audio exists in WebM, and AV1 video in AVIF. For still images, assert dimensions and alpha auxiliary presence when the input reported alpha. For video, assert source dimensions and orientation contract. For audio, assert channel count when the target supports it.

- [x] **Step 8: Run Task 3 gates**

Run:

```bash
swift run OptimizeAnythingCoreTests
swift build
git diff --check
```

Expected: every unit test and build passes; no installed FFmpeg is required.

- [x] **Step 9: Commit and push Task 3**

Stage Task 3 paths explicitly. Commit `feat(conversion): run and validate local media conversions`, push, and prove `0 0`.

### Task 4: Serial Queue and Drain Summary

**Files:**
- Create: `Sources/OptimizeAnythingCore/Queue/DrainSummary.swift`
- Create: `Sources/OptimizeAnythingCore/Queue/ConversionQueue.swift`
- Create: `Tests/OptimizeAnythingCoreTests/ConversionQueueTests.swift`
- Create: `Tests/OptimizeAnythingCoreTests/DrainSummaryTests.swift`

**Interfaces:**
- Consumes: `ConversionPlan`, `ConversionOutcome`, and `ConversionServicing` from Tasks 2–3.
- Produces: `ConversionJob`, `ConversionJobState`, `QueueSnapshot`, `DrainSummary`, `ConversionQueue.enqueue(_:)`, `cancel(jobID:)`, `retry(failedJobID:with:)`, `snapshots()`, and `drainEvents()` for the MainActor view model.

`ConversionQueueTests.swift` defines fixed UUIDs ending in `101` and `102`,
`plan(id:)` that uses `makePlan` and replaces its ID, `output(_:)` beside that
plan's fixture, and actor `ControlledConverter: ConversionServicing`. The fake
records `startedIDs`, suspends each conversion in a checked continuation,
provides `waitUntilStarted(_:)`, `finish(_:with:)`, and
`finishAllSuccessfully()`, and records cancel calls. Every wait uses the shared
bounded `eventually` helper.

- [x] **Step 1: Write failing serial and drain-boundary tests**

Use a controlled fake whose continuation lets the test prove no second call begins early:

```swift
func testQueueRunsExactlyOneConversionAtATime() async throws {
    let converter = ControlledConverter()
    let queue = ConversionQueue(converter: converter)
    await queue.enqueue([plan(id: .one), plan(id: .two)])
    await converter.waitUntilStarted(.one)
    XCTAssertEqual(await converter.startedIDs, [.one])
    await converter.finish(.one, with: .succeeded(output: output(.one), outputByteCount: 40))
    await converter.waitUntilStarted(.two)
    XCTAssertEqual(await converter.startedIDs, [.one, .two])
}

func testDropsDuringActiveWorkShareOneDrainSummary() async throws {
    let converter = ControlledConverter()
    let queue = ConversionQueue(converter: converter)
    let stream = await queue.drainEvents()
    let firstDrain = Task { () -> DrainSummary? in
        for await summary in stream { return summary }
        return nil
    }
    await queue.enqueue([plan(id: .one)])
    await converter.waitUntilStarted(.one)
    await queue.enqueue([plan(id: .two)])
    await converter.finishAllSuccessfully()
    let summary = await firstDrain.value
    XCTAssertEqual(summary?.succeededCount, 2)
}
```

- [x] **Step 2: Run queue tests and observe missing queue types**

Run: `swift run OptimizeAnythingCoreTests`

Expected: compilation fails because queue and summary types do not exist.

- [x] **Step 3: Implement immutable snapshots and terminal summaries**

Use these observable values:

```swift
public enum ConversionJobState: Equatable, Sendable {
    case queued
    case probing
    case converting(progress: Double)
    case validating
    case succeeded(output: URL, outputByteCount: Int64)
    case failed(ConversionFailure)
    case canceled
}

public struct ConversionJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let plan: ConversionPlan
    public var state: ConversionJobState
}

public struct QueueSnapshot: Equatable, Sendable {
    public let jobs: [ConversionJob]
    public let unfinishedCount: Int
    public let isRunning: Bool
}

public struct DrainSummary: Equatable, Sendable {
    public let succeededCount: Int
    public let failedCount: Int
    public let canceledCount: Int
    public let bytesSaved: Int64
    public let lastSuccessfulOutput: URL?
}

public protocol QueueServing: Sendable {
    func enqueue(_ plans: [ConversionPlan]) async
    func cancel(jobID: UUID) async
    func retry(failedJobID: UUID, with plan: ConversionPlan) async throws
    func snapshots() async -> AsyncStream<QueueSnapshot>
    func drainEvents() async -> AsyncStream<DrainSummary>
}

public actor ConversionQueue: QueueServing {
    public init(converter: any ConversionServicing)
    public func enqueue(_ plans: [ConversionPlan]) async
    public func cancel(jobID: UUID) async
    public func retry(failedJobID: UUID, with plan: ConversionPlan) async throws
    public func snapshots() async -> AsyncStream<QueueSnapshot>
    public func drainEvents() async -> AsyncStream<DrainSummary>
}
```

`ConversionQueue` is an actor. It starts a single private drain task only when transitioning from idle with queued jobs. Progress is clamped and published no more frequently than every 100 ms except terminal `1.0`. Terminal state cannot transition. `retry(failedJobID:with:)` accepts a newly rebuilt plan from the caller, verifies the referenced job failed, preserves the prior terminal job, and enqueues the new ID. `drainEvents()` emits once only when no active or queued work remains and clears the accumulator after emission; session jobs remain in snapshots until app termination.

- [x] **Step 4: Add cancel, retry, byte-savings, and terminal-state tests**

Assert cancel forwards to `ConversionServicing.cancel(jobID:)`, removes temp through the service, and continues with the next job. Assert byte savings uses `max(0, sourceByteCount - outputByteCount)` and never reports negative savings. Assert retry does not mutate the prior failed job.

- [x] **Step 5: Run Task 4 gates**

Run:

```bash
swift run OptimizeAnythingCoreTests
swift build
git diff --check
```

Expected: queue timing tests are deterministic and all checks pass.

- [x] **Step 6: Commit and push Task 4**

Stage Task 4 paths. Commit `feat(queue): orchestrate serial conversion batches`, push, and prove `0 0` parity.

### Task 5: Native Menu Bar Drop, Popover, Settings, and Notifications

**Files:**
- Modify: `Package.swift`
- Create: `Sources/OptimizeAnythingMac/AppViewModel.swift`
- Create: `Sources/OptimizeAnythingMac/ApplicationController.swift`
- Create: `Sources/OptimizeAnythingMac/StatusBar/StatusBarController.swift`
- Create: `Sources/OptimizeAnythingMac/StatusBar/StatusBarDropView.swift`
- Create: `Sources/OptimizeAnythingMac/Views/PopoverView.swift`
- Create: `Sources/OptimizeAnythingMac/Views/JobRowView.swift`
- Create: `Sources/OptimizeAnythingMac/Views/SettingsView.swift`
- Create: `Sources/OptimizeAnythingMac/Views/SettingsWindowController.swift`
- Create: `Sources/OptimizeAnythingMac/Notifications/LocalNotificationService.swift`
- Create: `Sources/OptimizeAnythingMac/FinderService.swift`
- Create: `Sources/OptimizeAnythingApp/main.swift`
- Create: `Sources/OptimizeAnythingApp/AppDelegate.swift`
- Create: `Tests/OptimizeAnythingMacTests/MacTestSupport.swift`
- Create: `Tests/OptimizeAnythingMacTests/StatusBarDropViewTests.swift`
- Create: `Tests/OptimizeAnythingMacTests/AppViewModelTests.swift`
- Create: `Tests/OptimizeAnythingMacTests/LocalNotificationServiceTests.swift`

**Interfaces:**
- Consumes: `MappingStore`, `DropAdmissionService`, `ConversionPlanner`, `ConversionQueue`, `QueueSnapshot`, and `DrainSummary`.
- Produces: A launchable accessory app, direct status-item and popover drops, queue UI actions, constrained settings, Finder reveal, and a native notification adapter.

At the start of this task, add the Mac library/product, executable product, and
Mac test target to `Package.swift` exactly as follows; all referenced paths now
have source in this task:

```swift
.library(name: "OptimizeAnythingMac", targets: ["OptimizeAnythingMac"]),
.executable(name: "OptimizeAnythingApp", targets: ["OptimizeAnythingApp"]),

.target(name: "OptimizeAnythingMac", dependencies: ["OptimizeAnythingCore"]),
.executableTarget(name: "OptimizeAnythingApp", dependencies: ["OptimizeAnythingMac"]),
.executableTarget(
    name: "OptimizeAnythingMacTests",
    dependencies: ["OptimizeAnythingMac"],
    path: "Tests/OptimizeAnythingMacTests"
),
```

`AppViewModel` depends on protocols instead of concrete globals so tests can
prove orchestration without macOS side effects:

```swift
public protocol NotificationServing: Sendable {
    func requestAuthorizationIfNeeded() async
    func deliver(_ summary: DrainSummary) async throws
}

public protocol FinderServing: Sendable {
    @MainActor func reveal(_ url: URL)
}

public struct ViewModelDependencies: Sendable {
    public let settings: any SettingsServing
    public let admission: any DropAdmitting
    public let planner: any ConversionPlanning
    public let queue: any QueueServing
    public let notifications: any NotificationServing
    public let finder: any FinderServing
}
```

Core actors conform through small extensions in their owning files.
`MacTestSupport.swift` defines `FakeSettingsStore`, `FakeAdmissionService`,
`FakePlanner`, `FakeQueue`, `FakeNotificationService`, and `FakeFinderService`
with recorded calls and deterministic `AsyncStream` continuations, plus
`ViewModelDependencies.acceptingFixtures()` and
`ViewModelDependencies(notificationStatus:)` used below. Every continuation is
finished in test teardown.

- [x] **Step 1: Write failing pasteboard URL and view-model tests**

Build an `NSPasteboard` with file URLs and non-file payloads. Assert only file URLs are returned in pasteboard order. Use fake store, planner, queue, notification, and Finder protocols for `AppViewModel`:

```swift
@MainActor
func testAcceptedDropRequestsNotificationOnceAndEnqueuesPlans() async throws {
    let dependencies = ViewModelDependencies.acceptingFixtures()
    let model = AppViewModel(dependencies: dependencies)
    await model.handleDrop([dependencies.wavURL, dependencies.movURL])
    XCTAssertEqual(dependencies.notification.authorizationRequestCount, 1)
    XCTAssertEqual(dependencies.queue.enqueuedPlans.map(\.input), [dependencies.wavURL, dependencies.movURL])
    await model.handleDrop([dependencies.pngURL])
    XCTAssertEqual(dependencies.notification.authorizationRequestCount, 1)
}

@MainActor
func testDeniedNotificationKeepsDrainSummaryInPopover() async {
    let dependencies = ViewModelDependencies(notificationStatus: .denied)
    let model = AppViewModel(dependencies: dependencies)
    await model.receiveDrain(.fixtureSuccess)
    XCTAssertEqual(model.lastDrainSummary, .fixtureSuccess)
    XCTAssertEqual(dependencies.notification.delivered.count, 0)
}
```

- [x] **Step 2: Run Mac tests and observe missing UI types**

Run: `swift run OptimizeAnythingMacTests`

Expected: compilation fails because the Mac target files do not exist.

- [x] **Step 3: Implement the MainActor adapter and application dependency graph**

`AppViewModel` is `@MainActor`, conforms to `ObservableObject`, and exposes published settings, snapshot, admission errors, last drain summary, drag highlight, and tool availability. It starts tasks consuming queue snapshot/drain streams, but cancels them in `deinit`. It calls admission and planning off the main actor and returns only immutable values.

`ApplicationController` creates the Application Support settings URL at:

```text
~/Library/Application Support/com.channprj.optimize-anything/settings.json
```

It resolves bundled `ffmpeg` and `ffprobe`, builds the core dependency graph once, creates `AppViewModel`, then creates the status bar and settings controllers. Missing tools are an explicit unavailable state that rejects conversion but still allows settings and quit.

- [x] **Step 4: Implement the direct status item drag surface**

Use an `NSView` overlay installed inside `NSStatusBarButton` because it can own closure-based `NSDraggingDestination` methods while preserving the native status item:

```swift
final class StatusBarDropView: NSView {
    var onClick: () -> Void = {}
    var onDragActiveChanged: (Bool) -> Void = { _ in }
    var onDropURLs: ([URL]) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
    override func draggingExited(_ sender: NSDraggingInfo?)
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool
    override func mouseDown(with event: NSEvent)
}
```

The overlay uses autoresizing width/height, forwards click to popover toggle, and extracts URLs with `readObjects(forClasses:options:)`. `StatusBarController` changes `statusItem.length` from square to a measured expanded width while dragging, uses a monochrome compression SF Symbol when idle, displays `Drop to optimize` while highlighted, displays unfinished count while running, and shows a warning symbol after a failed drain until the popover opens.

- [x] **Step 5: Implement the SwiftUI popover and constrained settings**

The 360-point popover shows title and aggregate state, active job first, queued jobs, then current-session terminal results. `JobRowView` exposes cancel only for active work, retry only for failed work, `Show Output` only for success, and `Show Source` for failure. The footer contains `Settings…`, `Show Output`, and `Quit`.

`SettingsView` lists rules by family. Editing source extensions normalizes on commit and validates before save. Target pickers use `RuleCatalog.targets(for:)`; quality picker uses exactly three localized labels. Add, disable, remove, and restore-default actions all save a complete valid `SettingsDocument`. A failed save leaves visible rules at the last saved document and displays `RuleValidationError` beside the editor.

- [x] **Step 6: Implement local notification and Finder services**

Wrap `UNUserNotificationCenter` behind a protocol with `authorizationStatus()`, `requestAuthorizationIfNeeded()`, and `deliver(_:)`. The request occurs only when `AppViewModel` accepts its first drop. Notification title is `Optimization complete` or `Optimization finished with issues`; body includes counts and formatted bytes saved, never a full path. Store the last output path only in notification `userInfo` for local click handling. `UNUserNotificationCenterDelegate` reveals it with `NSWorkspace.activateFileViewerSelecting`.

When authorization is denied or delivery errors, leave `lastDrainSummary` published and do not fail any job. When the app is active, delegate presentation includes banner and sound so the native result is still observable.

- [x] **Step 7: Implement accessory app launch and guarded quit**

`main.swift` creates `NSApplication.shared`, assigns `AppDelegate`, sets `.accessory`, and calls `run()`. `AppDelegate.applicationDidFinishLaunching` retains `ApplicationController`. Before termination, if unfinished count is nonzero, return `.terminateLater`, show an `NSAlert` with `Keep Waiting` and `Cancel Jobs and Quit`, and reply only after the chosen path settles.

- [x] **Step 8: Run Task 5 gates and a source-level app smoke**

Run:

```bash
swift run OptimizeAnythingCoreTests
swift run OptimizeAnythingMacTests
swift build -c release --product OptimizeAnythingApp
.build/release/OptimizeAnythingApp &
pgrep -x OptimizeAnythingApp
```

Terminate the smoke process normally after confirming it stays alive. Expected: tests/build pass, one process exists, and the app exposes a status item even though packaged tools are not yet present.

- [x] **Step 9: Commit and push Task 5**

Stage Task 5 paths. Commit `feat(macos): add menu bar drop and settings experience`, push, and prove `0 0`.

### Task 6: Reproducible LGPL Toolchain and App Bundle

**Files:**
- Create: `Dependencies/ffmpeg/versions.env`
- Create: `scripts/build-ffmpeg.sh`
- Create: `scripts/build-app.sh`
- Create: `scripts/test-packaging.sh`
- Create: `App/Info.plist`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `.gitignore`
- Test: `scripts/test-packaging.sh`

**Interfaces:**
- Consumes: Release executable from Task 5 and the tool paths expected by `ApplicationController`.
- Produces: `build/vendor/ffmpeg/bin/{ffmpeg,ffprobe}` and `dist/Optimize Anything.app` with verified nested signatures and licenses.

- [x] **Step 1: Record exact source versions, URLs, and verified SHA-256 values**

`Dependencies/ffmpeg/versions.env` contains only these shell-safe constants:

```bash
FFMPEG_VERSION=8.0
FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz
FFMPEG_SHA256=b2751fccb6cc4c77708113cd78b561059b6fa904b24162fa0be2d60273d27b8e
LIBVPX_VERSION=1.15.0
LIBVPX_URL=https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.0.tar.gz
LIBVPX_SHA256=e935eded7d81631a538bfae703fd1e293aad1c7fd3407ba00440c95105d2011e
LIBAOM_VERSION=3.12.1
LIBAOM_URL=https://storage.googleapis.com/aom-releases/libaom-3.12.1.tar.gz
LIBAOM_SHA256=9e9775180dec7dfd61a79e00bda3809d43891aee6b2e331ff7f26986207ea22e
OPUS_VERSION=1.5.2
OPUS_URL=https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz
OPUS_SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
```

- [x] **Step 2: Write the packaging test before the build scripts**

`scripts/test-packaging.sh` exits nonzero unless all of these hold:

```bash
test -x "dist/Optimize Anything.app/Contents/MacOS/OptimizeAnything"
test -x "dist/Optimize Anything.app/Contents/Resources/ffmpeg"
test -x "dist/Optimize Anything.app/Contents/Resources/ffprobe"
test -f "dist/Optimize Anything.app/Contents/Resources/THIRD_PARTY_NOTICES.md"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "dist/Optimize Anything.app/Contents/Info.plist")" = true
codesign --verify --deep --strict "dist/Optimize Anything.app"
"dist/Optimize Anything.app/Contents/Resources/ffmpeg" -hide_banner -buildconf 2>&1 | grep -q -- '--disable-gpl'
"dist/Optimize Anything.app/Contents/Resources/ffmpeg" -hide_banner -buildconf 2>&1 | grep -q -- '--disable-nonfree'
"dist/Optimize Anything.app/Contents/Resources/ffmpeg" -hide_banner -encoders 2>&1 | grep -q libvpx-vp9
"dist/Optimize Anything.app/Contents/Resources/ffmpeg" -hide_banner -encoders 2>&1 | grep -q libaom-av1
"dist/Optimize Anything.app/Contents/Resources/ffmpeg" -hide_banner -encoders 2>&1 | grep -q libopus
```

Run: `zsh scripts/test-packaging.sh`

Expected: fails immediately because the app bundle does not exist.

- [x] **Step 3: Implement the pinned source builder**

`scripts/build-ffmpeg.sh` uses `set -euo pipefail`, sources `versions.env`, works only below repository-local `build/vendor`, downloads through `curl --fail --location`, verifies each archive with `shasum -a 256 -c`, and never trusts an existing archive until it re-verifies. Build static arm64 dependencies in this order: Opus with Autotools, libvpx with its configure script, libaom with CMake, then FFmpeg.

FFmpeg configure must include:

```bash
--arch=arm64
--target-os=darwin
--enable-static
--disable-shared
--disable-debug
--disable-doc
--disable-ffplay
--disable-network
--disable-gpl
--disable-nonfree
--enable-libaom
--enable-libvpx
--enable-libopus
```

Pass repository-local include/library/pkg-config paths, `--pkg-config-flags=--static`, and a deployment target of macOS 14. Copy only `ffmpeg` and `ffprobe` to `build/vendor/ffmpeg/bin`. Write the exact configure line and `git diff` equivalent for unmodified release tarballs to `build/vendor/ffmpeg/source-offer/BUILD.txt`, then copy the hash manifest, license files, and source archives into that source-offer directory. Do not invoke or copy the machine's existing GPL-enabled FFmpeg.

- [x] **Step 4: Implement deterministic app bundle assembly**

`App/Info.plist` fixes these values:

```xml
<key>CFBundleIdentifier</key><string>com.channprj.optimize-anything</string>
<key>CFBundleExecutable</key><string>OptimizeAnything</string>
<key>CFBundleName</key><string>Optimize Anything</string>
<key>CFBundleDisplayName</key><string>Optimize Anything</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
```

`scripts/build-app.sh` builds the arm64 release executable, reconstructs only the explicit `dist/Optimize Anything.app` target, copies the executable as `Contents/MacOS/OptimizeAnything`, copies tools, notices, and the corresponding source offer to `Contents/Resources`, strips release symbols, signs FFmpeg and FFprobe first with ad-hoc identity `-`, signs the outer bundle last, then runs `scripts/test-packaging.sh`. It never deletes a path derived from an unset variable or a path broader than the exact app bundle.

- [x] **Step 5: Write third-party notice content**

`THIRD_PARTY_NOTICES.md` identifies FFmpeg 8.0 under LGPL-2.1-or-later, libvpx 1.15.0 under BSD-3-Clause, libaom 3.12.1 under BSD-2-Clause, and Opus 1.5.2 under BSD-3-Clause. `scripts/build-app.sh` copies the matching source offer into `Contents/Resources/source-offer`, and the notice requires it to remain with every distributed binary.

- [x] **Step 6: Build tools and app, then run packaging gates**

Run:

```bash
zsh scripts/build-ffmpeg.sh
zsh scripts/build-app.sh
zsh scripts/test-packaging.sh
file "dist/Optimize Anything.app/Contents/MacOS/OptimizeAnything"
otool -L "dist/Optimize Anything.app/Contents/Resources/ffmpeg"
git diff --check
```

Expected: binaries report arm64, no dynamic dependency points into Homebrew or a developer workspace, signatures pass, build configuration contains both disable flags, and required encoders are present.

- [x] **Step 7: Commit and push Task 6**

Do not commit `build/` or `dist/`. Stage only the manifest, scripts, Info.plist, notice, and `.gitignore`. Commit `build(macos): package reproducible media toolchain`, push, and prove `0 0`.

### Task 7: Real-Media Integration and Runtime Acceptance

**Files:**
- Modify: `Package.swift`
- Create: `scripts/generate-fixtures.sh`
- Create: `scripts/integration-test.sh`
- Create: `scripts/runtime-smoke.sh`
- Create: `scripts/check.sh`
- Create: `Tests/OptimizeAnythingIntegrationTests/MediaConversionIntegrationTests.swift`
- Modify: `Sources/OptimizeAnythingApp/AppDelegate.swift`
- Modify: `Sources/OptimizeAnythingMac/ApplicationController.swift`

**Interfaces:**
- Consumes: Completed core, queue, native UI, and app bundle.
- Produces: Deterministic fixture generation, automated real-codec acceptance, runtime process checks, and an explicit manual-native evidence checklist.

Add an `.executableTarget` named `OptimizeAnythingIntegrationTests`, depending
on `OptimizeAnythingCore` and using `Tests/OptimizeAnythingIntegrationTests`,
when the integration test source is created.

- [x] **Step 1: Generate deterministic fixtures with the bundled tools**

`scripts/generate-fixtures.sh <directory>` recreates only its explicit target and uses bundled FFmpeg lavfi inputs:

```bash
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=1' -c:a pcm_s16le voice.wav
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1' -f lavfi -i 'sine=frequency=880:duration=1' -c:v prores_ks -c:a pcm_s16le -shortest movie.mov
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i 'color=c=0x3366cc:s=96x64:d=1' -frames:v 1 opaque.png
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i 'color=c=red@0.4:s=96x64:d=1,format=rgba' -frames:v 1 alpha.png
```

The script records each source SHA-256 before tests.

- [x] **Step 2: Write real conversion integration tests**

Tests require `OPTIMIZE_ANYTHING_TOOL_DIR` and `OPTIMIZE_ANYTHING_FIXTURE_DIR`;
the integration executable skips only when invoked directly without them.
`scripts/integration-test.sh` verifies tools exist, sets both variables,
generates fixtures in a fresh `mktemp -d` directory, runs the executable, and
therefore never skips in the acceptance gate.

The test class calls the real `ConversionService` and asserts:

```swift
try requireEqual(outputM4A.audioCodec, "aac", "M4A codec")
try require(outputM4A.containerNames.contains("mov"), "M4A container")
try requireEqual(outputWebM.videoCodec, "vp9", "WebM video codec")
try requireEqual(outputWebM.audioCodec, "opus", "WebM audio codec")
try requireEqual(outputAVIF.videoCodec, "av1", "AVIF codec")
try requireEqual(outputAVIF.width, 96, "AVIF width")
try requireEqual(outputAVIF.height, 64, "AVIF height")
try require(alphaAVIF.hasAlpha, "Alpha AVIF")
try requireEqual(try sha256(source), originalHash, "source hash")
try requireEqual(try hiddenTemporaryFiles(in: fixtureDirectory), [], "temporary files")
```

Add collision bytes before conversion and assert they remain byte-identical. Add a corrupt `.mov` and a long generated job canceled after the process begins; neither may create a final or temporary artifact.

- [x] **Step 3: Add a test-only ingest launch argument without weakening real drag acceptance**

When launched with `--ingest <absolute-file>...`, `AppDelegate` forwards those file URLs through the exact `AppViewModel.handleDrop` path after startup. This is not a second conversion implementation; it is a deterministic automation seam for packaged runtime smoke. The normal launch has no arguments and exposes the direct status item drag target.

`scripts/runtime-smoke.sh` launches the packaged app with generated fixtures, waits with a bounded deadline for expected siblings, checks one process, validates outputs with bundled FFprobe, confirms source hashes, reads `LSUIElement=true`, and terminates the app normally. A timeout prints app logs and exits nonzero.

- [x] **Step 4: Create the full check script**

`scripts/check.sh` runs in this order and stops on the first failure:

```bash
swift run OptimizeAnythingCoreTests
swift run OptimizeAnythingMacTests
swift build -c release --product OptimizeAnythingApp
zsh scripts/build-app.sh
zsh scripts/integration-test.sh
zsh scripts/runtime-smoke.sh
zsh scripts/test-packaging.sh
git diff --check
```

It reports the test counts and artifact path. It does not suppress skipped tests or ignore a failing command.

- [x] **Step 5: Run automated acceptance**

Run: `zsh scripts/check.sh`

Expected: all unit, integration, build, package, signature, and runtime-ingest checks pass with verified source hashes and codecs.

- [ ] **Step 6: Perform native user-facing evidence checks**

Launch `dist/Optimize Anything.app` normally. Using Finder and the generated fixture directory, prove each item independently:

1. No Dock item appears and one menu bar item appears.
2. Dragging supported files over the menu item expands it to `Drop to optimize`; leaving restores it.
3. Dropping WAV, MOV, opaque PNG, and alpha PNG enqueues all four without opening the popover automatically.
4. Clicking the item shows active/queued progress and current-session results.
5. Outputs appear beside sources with the collision policy and Finder reveal selects the last output.
6. A granted notification permission produces one native summary after the queue drains.
7. With notification permission denied, conversion still succeeds and the summary remains in the popover.
8. Canceling an active generated long video removes its temporary output and advances the queue.

Capture concrete evidence where the environment allows it. If macOS TCC, notification settings, GUI access, or native pixel capture is unavailable, report that item separately as unverified; automated checks cannot stand in for it.

- [x] **Step 7: Commit and push Task 7**

Stage Task 7 test, script, and automation-seam paths. Commit `test(integration): verify real media optimization flows`, push, and prove `0 0`.

### Task 8: Usage Documentation and Completion Audit

**Files:**
- Create: `README.md`
- Modify: `docs/superpowers/specs/2026-08-14-optimize-anything-design.md`
- Modify: `docs/superpowers/plans/2026-08-14-optimize-anything-mvp.md`

**Interfaces:**
- Consumes: Verified commands and observed behavior from Tasks 1–7.
- Produces: A truthful private-repository landing page and checked-off durable plan.

- [x] **Step 1: Write README from verified behavior**

Document product purpose, macOS 14/Apple Silicon requirement, supported default mappings and exact quality profiles, direct menu bar and popover drop flows, output naming and original preservation, settings location, notification behavior, local build commands, FFmpeg source/license workflow, test commands, privacy statement, known MVP exclusions, and troubleshooting for missing notification permission or insufficient disk space.

Do not claim Developer ID signing, notarization, Intel support, folder recursion, persistent history, automatic updates, or a public release.

- [x] **Step 2: Reconcile spec and plan status with evidence**

Change the PRD status to `Implemented and verified` only if every MVP Definition of Done item has authoritative evidence. Check each plan box only after its command or observation succeeds. Leave unavailable native evidence unchecked and describe it in the final report rather than weakening its requirement.

- [x] **Step 3: Run the complete final gate from a clean build state**

Run:

```bash
zsh scripts/check.sh
git status --short
git diff --check
```

Expected: checks pass and only Task 8 documentation paths are modified.

- [x] **Step 4: Commit and push Task 8**

Because `docs/superpowers` is globally ignored, explicitly force-stage only the intended tracked spec and plan if ordinary staging omits them. Stage `README.md` normally. Commit `docs: document local optimization workflow`, push, and prove `0 0`.

- [x] **Step 5: Perform the `$gcpr` completion audit**

Re-read the original Korean request and the complete PRD. For every story OA-1 through OA-5 and every Success Criterion, record the current authoritative evidence. Run:

```bash
git log --oneline 95cd98d..HEAD
git status --short --branch
git rev-list --left-right --count HEAD...@{u}
git rev-parse HEAD
git ls-remote origin refs/heads/main
gh repo view channprj/optimize-anything --json visibility,url,defaultBranchRef
```

Expected: clean tree, `0 0`, identical local/live remote SHA, `PRIVATE` visibility, and `main` default branch. If final verification creates a correction, make a new truthful `fix`, `test`, `build`, or `docs` checkpoint and push it without rewriting any published commit.

## Spec Coverage Self-Review

| Approved requirement | Implementing tasks | Proof gate |
| --- | --- | --- |
| Direct menu bar and popover file drop | 5, 7 | Mac tests plus real Finder drag |
| Default configurable format mappings | 1, 2, 5 | Rule, argument, settings UI tests |
| Background serial conversion | 3, 4 | Transaction and controlled-concurrency tests |
| Output beside source without source mutation | 2, 3, 7 | Collision tests, SHA-256, integration fixtures |
| Safe temp/final transaction and cleanup | 2, 3, 7 | failure/cancel/race integration cases |
| Progress, cancel, retry, Finder actions | 4, 5, 7 | queue/Mac tests and popover observation |
| One native completion notification | 4, 5, 7 | drain test, notification fake, granted native observation |
| Notification denial fallback | 5, 7 | fake denial test and denied native observation |
| Versioned settings and user-choice preservation | 1, 5 | atomic store and migration tests |
| Local privacy and shell-free execution | 2, 3, 8 | exact argument arrays, process boundary review, README |
| LGPL-compatible bundled FFmpeg/FFprobe | 6, 7 | hashes, buildconf, codecs, notices, app bundle test |
| Apple Silicon macOS 14 accessory app | 5, 6, 7 | manifest, Info.plist, `file`, runtime/native observation |
| Private GitHub and realtime push parity | every task | private repo query and `0 0` after every checkpoint |

The plan contains no independent subsystem that can ship without the others: each task is a testable layer in the single menu-bar conversion flow. The implementation stays inline in this session because workspace instructions do not authorize subagent dispatch; use `superpowers:executing-plans` for task-by-task execution and preserve the checkpoint sequence above.
