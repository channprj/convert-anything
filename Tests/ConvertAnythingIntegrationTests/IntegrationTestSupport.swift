import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

struct IntegrationEnvironment: Sendable {
  let fixtureDirectory: URL
  let ffmpeg: URL
  let ffprobe: URL

  static func load() -> IntegrationEnvironment? {
    let environment = ProcessInfo.processInfo.environment
    guard let toolPath = environment["CONVERT_ANYTHING_TOOL_DIR"],
      let fixturePath = environment["CONVERT_ANYTHING_FIXTURE_DIR"]
    else {
      return nil
    }
    return IntegrationEnvironment(
      fixtureDirectory: URL(fileURLWithPath: fixturePath, isDirectory: true),
      ffmpeg: URL(fileURLWithPath: toolPath).appendingPathComponent("ffmpeg"),
      ffprobe: URL(fileURLWithPath: toolPath).appendingPathComponent("ffprobe")
    )
  }

  func workingCopy(of name: String) throws -> URL {
    let directory =
      fixtureDirectory
      .appendingPathComponent("test-runs", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = fixtureDirectory.appendingPathComponent(name)
    let destination = directory.appendingPathComponent(name)
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
  }

  func service() -> ConversionService {
    let executor = FoundationCommandExecutor()
    return ConversionService(
      probe: FFprobeClient(executable: ffprobe, executor: executor),
      runner: FFmpegRunner(executable: ffmpeg, executor: executor)
    )
  }

  func probe(_ url: URL) async throws -> InputMediaInfo {
    try await FFprobeClient(executable: ffprobe, executor: FoundationCommandExecutor())
      .probe(url, commandID: UUID())
  }

  func decodedAlphaPlane(from url: URL, streamIndex: Int? = nil) async throws -> Data {
    var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", url.path]
    if let streamIndex {
      arguments += ["-map", "0:v:\(streamIndex)"]
    } else {
      arguments += ["-vf", "alphaextract"]
    }
    arguments += ["-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1"]

    let result = try await FoundationCommandExecutor().execute(
      CommandRequest(id: UUID(), executable: ffmpeg, arguments: arguments)
    ) { _ in }
    guard result.terminationStatus == 0 else {
      throw TestFailure(description: "Could not decode alpha plane from \(url.lastPathComponent)")
    }
    return result.standardOutput
  }
}

func integrationPlan(for input: URL, target: TargetFormat) throws -> ConversionPlan {
  let rule = ConversionRule(
    id: UUID(),
    family: target.family,
    sourceExtensions: [input.pathExtension.lowercased()],
    target: target,
    quality: .balanced,
    isEnabled: true
  )
  let jobID = UUID()
  return ConversionPlan(
    id: jobID,
    input: input,
    output: try OutputPathResolver().resolve(input: input, target: target, jobID: jobID),
    rule: rule,
    sourceByteCount: Int64(try Data(contentsOf: input).count)
  )
}

func defaultRule(for sourceExtension: String) throws -> ConversionRule {
  guard
    let rule = RuleCatalog.defaultRules.first(where: {
      $0.isEnabled && $0.sourceExtensions.contains(sourceExtension)
    })
  else {
    throw TestFailure(
      description: "\(sourceExtension.uppercased()) has no enabled default conversion rule"
    )
  }
  return rule
}

func successfulOutput(from outcome: ConversionOutcome) throws -> URL {
  guard case .succeeded(let output, _) = outcome else {
    throw TestFailure(description: "Expected success, got \(outcome)")
  }
  return output
}

func sha256(_ url: URL) throws -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
  process.arguments = ["-a", "256", url.path]
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0,
    let digest = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .split(separator: " ").first
  else {
    throw TestFailure(description: "Could not hash \(url.lastPathComponent)")
  }
  return String(digest)
}

func hiddenTemporaryFiles(in directory: URL) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: nil,
    options: []
  ).filter { $0.lastPathComponent.contains(".convert-anything-") }
}
