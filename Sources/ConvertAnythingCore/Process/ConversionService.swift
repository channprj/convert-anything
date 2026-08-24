import Foundation

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

  public init(category: ConversionFailureCategory, message: String) {
    self.category = category
    self.message = message
  }
}

public enum ConversionOutcome: Equatable, Sendable {
  case succeeded(output: URL, outputByteCount: Int64)
  case failed(ConversionFailure)
  case canceled

  public var failureCategory: ConversionFailureCategory? {
    guard case .failed(let failure) = self else { return nil }
    return failure.category
  }
}

public protocol ConversionServicing: Sendable {
  func convert(
    _ plan: ConversionPlan,
    progress: @escaping @Sendable (Double) -> Void
  ) async -> ConversionOutcome
  func cancel(jobID: UUID) async
}

public final class ConversionService: ConversionServicing, @unchecked Sendable {
  private static let mp4FamilyContainers = Set(["mov", "mp4", "m4a", "3gp", "3g2", "mj2"])

  private let probe: FFprobeClient
  private let runner: FFmpegRunner
  private let fileManager: FileManager
  private let cancellations = CancellationRegistry()

  public init(
    probe: FFprobeClient,
    runner: FFmpegRunner,
    fileManager: FileManager = .default
  ) {
    self.probe = probe
    self.runner = runner
    self.fileManager = fileManager
  }

  public func convert(
    _ plan: ConversionPlan,
    progress: @escaping @Sendable (Double) -> Void
  ) async -> ConversionOutcome {
    if await cancellations.consume(plan.id) {
      return .canceled
    }
    guard fileManager.fileExists(atPath: plan.input.path) else {
      return failure(.inputUnavailable, "The input file is no longer available")
    }

    let inputMedia: InputMediaInfo
    do {
      inputMedia = try await probe.probe(plan.input, commandID: plan.id)
    } catch {
      if await cancellations.consume(plan.id) { return .canceled }
      return probeFailure(error, postcondition: false)
    }
    if await cancellations.consume(plan.id) { return .canceled }

    let plan = resolvedPlan(for: plan, inputMedia: inputMedia)

    defer {
      try? fileManager.removeItem(at: plan.output.temporary)
    }

    if fileManager.fileExists(atPath: plan.output.temporary.path) {
      do {
        try fileManager.removeItem(at: plan.output.temporary)
      } catch {
        return failure(.finalizationFailed, "A stale temporary file could not be removed")
      }
    }

    let result: CommandResult
    do {
      result = try await runner.run(plan: plan, media: inputMedia, progress: progress)
    } catch {
      if await cancellations.consume(plan.id) { return .canceled }
      return failure(.encoderUnavailable, "The bundled encoder could not be launched")
    }
    if await cancellations.consume(plan.id) { return .canceled }

    guard result.terminationStatus == 0 else {
      let message = result.lastStandardErrorLine(fallback: "Media conversion failed")
      let category: ConversionFailureCategory =
        isInvalidMediaMessage(message)
        ? .invalidMedia : .encoderFailed
      return failure(category, message)
    }

    guard let outputByteCount = regularFileSize(at: plan.output.temporary), outputByteCount > 0
    else {
      return failure(.invalidOutput, "The encoder did not produce a non-empty output")
    }

    let outputMedia: InputMediaInfo
    do {
      outputMedia = try await probe.probe(plan.output.temporary, commandID: plan.id)
    } catch {
      if await cancellations.consume(plan.id) { return .canceled }
      return probeFailure(error, postcondition: true)
    }
    if await cancellations.consume(plan.id) { return .canceled }

    guard validates(output: outputMedia, against: inputMedia, target: plan.rule.target) else {
      return failure(.invalidOutput, "The encoded media does not match the requested format")
    }
    do {
      try preservePOSIXPermissions(from: plan.input, on: plan.output.temporary)
    } catch {
      return failure(.finalizationFailed, "The output file permissions could not be secured")
    }
    guard !fileManager.fileExists(atPath: plan.output.final.path) else {
      return failure(.finalizationFailed, "The selected output name became unavailable")
    }

    do {
      try fileManager.moveItem(at: plan.output.temporary, to: plan.output.final)
    } catch {
      return failure(.finalizationFailed, "The completed output could not be finalized")
    }
    return .succeeded(output: plan.output.final, outputByteCount: outputByteCount)
  }

  public func cancel(jobID: UUID) async {
    await cancellations.mark(jobID)
    await runner.cancel(jobID: jobID)
  }

  /// Re-resolves the output paths once the probed input settles a dynamic
  /// target extension (jpegOrPng picks png only when alpha must survive).
  private func resolvedPlan(for plan: ConversionPlan, inputMedia: InputMediaInfo)
    -> ConversionPlan
  {
    let requiredExtension = plan.rule.target.fileExtension(hasAlpha: inputMedia.hasAlpha)
    guard plan.output.final.pathExtension != requiredExtension,
      let output = try? OutputPathResolver().resolve(
        input: plan.input,
        fileExtension: requiredExtension,
        jobID: plan.id
      )
    else {
      return plan
    }
    return ConversionPlan(
      id: plan.id,
      input: plan.input,
      output: output,
      rule: plan.rule,
      sourceByteCount: plan.sourceByteCount
    )
  }

  private func regularFileSize(at url: URL) -> Int64? {
    guard
      let attributes = try? fileManager.attributesOfItem(atPath: url.path),
      let type = attributes[.type] as? FileAttributeType,
      type == .typeRegular,
      let size = attributes[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }

  private func preservePOSIXPermissions(from source: URL, on output: URL) throws {
    let sourceAttributes = try fileManager.attributesOfItem(atPath: source.path)
    guard let permissions = sourceAttributes[.posixPermissions] as? NSNumber else {
      throw FilePermissionError.sourcePermissionsUnavailable
    }
    try fileManager.setAttributes(
      [.posixPermissions: permissions],
      ofItemAtPath: output.path
    )
  }

  private func validates(
    output: InputMediaInfo,
    against input: InputMediaInfo,
    target: TargetFormat
  ) -> Bool {
    switch target {
    case .m4a:
      return !Self.mp4FamilyContainers.isDisjoint(with: output.containerNames)
        && output.audioCodec == "aac"
        && matchingOptional(input.channelCount, output.channelCount)
    case .mp3:
      return output.containerNames.contains("mp3")
        && output.audioCodec == "mp3"
        && matchingOptional(input.channelCount, output.channelCount)
    case .mp4:
      let audioMatches = input.audioCodec == nil || output.audioCodec == "aac"
      return !Self.mp4FamilyContainers.isDisjoint(with: output.containerNames)
        && output.videoCodec == "h264"
        && audioMatches
        && matchingOptional(input.width, output.width)
        && matchingOptional(input.height, output.height)
        && input.rotationDegrees == output.rotationDegrees
    case .jpegOrPng:
      let expectedCodec = input.hasAlpha ? "png" : "mjpeg"
      let alphaMatches = !input.hasAlpha || output.hasAlpha
      return output.videoCodec == expectedCodec
        && matchingOptional(input.width, output.width)
        && matchingOptional(input.height, output.height)
        && alphaMatches
    case .webm:
      let audioMatches = input.audioCodec == nil || output.audioCodec == "opus"
      return output.containerNames.contains("webm")
        && output.videoCodec == "vp9"
        && audioMatches
        && matchingOptional(input.width, output.width)
        && matchingOptional(input.height, output.height)
        && input.rotationDegrees == output.rotationDegrees
    case .avif:
      let alphaMatches = !input.hasAlpha || output.hasAlpha
      return output.containerNames.contains("avif")
        && output.videoCodec == "av1"
        && matchingOptional(input.width, output.width)
        && matchingOptional(input.height, output.height)
        && alphaMatches
    }
  }

  private func matchingOptional<T: Equatable>(_ input: T?, _ output: T?) -> Bool {
    input == nil || input == output
  }

  private func probeFailure(_ error: any Error, postcondition: Bool) -> ConversionOutcome {
    if error is CommandExecutorError {
      return failure(.encoderUnavailable, "The bundled media probe could not be launched")
    }
    if postcondition {
      return failure(.invalidOutput, "The encoded output could not be inspected")
    }
    switch error {
    case MediaProbeError.rejected(let message):
      return failure(.invalidMedia, message)
    default:
      return failure(.invalidMedia, "The input is not valid media")
    }
  }

  private func failure(
    _ category: ConversionFailureCategory,
    _ message: String
  ) -> ConversionOutcome {
    .failed(ConversionFailure(category: category, message: message))
  }

  private func isInvalidMediaMessage(_ message: String) -> Bool {
    let lowered = message.lowercased()
    return lowered.contains("invalid data")
      || lowered.contains("error while decoding")
      || lowered.contains("could not find codec parameters")
  }
}

private enum FilePermissionError: Error {
  case sourcePermissionsUnavailable
}

private actor CancellationRegistry {
  private var canceledJobIDs = Set<UUID>()

  func mark(_ jobID: UUID) {
    canceledJobIDs.insert(jobID)
  }

  func consume(_ jobID: UUID) -> Bool {
    canceledJobIDs.remove(jobID) != nil
  }
}
