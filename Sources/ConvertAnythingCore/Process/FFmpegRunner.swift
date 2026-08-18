import Foundation

public struct FFmpegProgressParser: Sendable {
  private let durationSeconds: Double?
  private var outputSeconds: Double?

  public init(durationSeconds: Double?) {
    self.durationSeconds = durationSeconds
  }

  public mutating func consume(_ line: String) -> Double? {
    if line.hasPrefix("out_time_us="),
      let microseconds = Double(line.dropFirst("out_time_us=".count))
    {
      outputSeconds = microseconds / 1_000_000
      return nil
    }
    guard line.hasPrefix("progress=") else { return nil }
    if line == "progress=end" { return 1 }
    guard line == "progress=continue",
      let durationSeconds,
      durationSeconds > 0,
      let outputSeconds
    else {
      return nil
    }
    return min(1, max(0, outputSeconds / durationSeconds))
  }
}

public struct FFmpegRunner: Sendable {
  private let executable: URL
  private let executor: any CommandExecuting

  public init(executable: URL, executor: any CommandExecuting) {
    self.executable = executable
    self.executor = executor
  }

  public func run(
    plan: ConversionPlan,
    media: InputMediaInfo,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> CommandResult {
    let parser = LockedProgressParser(durationSeconds: media.durationSeconds, progress: progress)
    let request = CommandRequest(
      id: plan.id,
      executable: executable,
      arguments: EncoderArguments.make(plan: plan, media: media)
    )
    return try await executor.execute(request) { line in
      parser.consume(line)
    }
  }

  public func cancel(jobID: UUID) async {
    await executor.terminate(commandID: jobID)
  }
}

private final class LockedProgressParser: @unchecked Sendable {
  private let lock = NSLock()
  private let progress: @Sendable (Double) -> Void
  private var parser: FFmpegProgressParser

  init(durationSeconds: Double?, progress: @escaping @Sendable (Double) -> Void) {
    parser = FFmpegProgressParser(durationSeconds: durationSeconds)
    self.progress = progress
  }

  func consume(_ line: String) {
    let value = lock.withLock { parser.consume(line) }
    if let value {
      progress(value)
    }
  }
}
