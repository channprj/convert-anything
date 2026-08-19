import Foundation

public protocol ConversionPlanning: Sendable {
  func plan(input: URL, rule: ConversionRule, jobID: UUID) async throws -> ConversionPlan
}

public struct ConversionPlanner: ConversionPlanning {
  private static let temporaryMargin: Int64 = 64 * 1_024 * 1_024

  private let availableCapacity: @Sendable (URL) throws -> Int64
  private let outputPathResolver: OutputPathResolver

  public init() {
    self.init(availableCapacity: Self.importantUsageCapacity)
  }

  public init(availableCapacity: @escaping @Sendable (URL) throws -> Int64) {
    self.availableCapacity = availableCapacity
    outputPathResolver = OutputPathResolver()
  }

  public func plan(input: URL, rule: ConversionRule, jobID: UUID) async throws -> ConversionPlan {
    let sourceExtension = input.pathExtension.lowercased()
    guard rule.isEnabled, rule.sourceExtensions.contains(sourceExtension) else {
      throw PlanningError.noEnabledRule(sourceExtension)
    }

    let sourceByteCount = try allocatedSize(of: input)
    let required = requiredCapacity(for: sourceByteCount, family: rule.family)
    let available: Int64
    do {
      available = max(0, try availableCapacity(input))
    } catch {
      throw PlanningError.inputUnavailable
    }
    guard available >= required else {
      throw PlanningError.insufficientDiskSpace(required: required, available: available)
    }

    let output = try outputPathResolver.resolve(input: input, target: rule.target, jobID: jobID)
    return ConversionPlan(
      id: jobID,
      input: input,
      output: output,
      rule: rule,
      sourceByteCount: sourceByteCount
    )
  }

  private func allocatedSize(of input: URL) throws -> Int64 {
    do {
      let values = try input.resourceValues(forKeys: [
        .isRegularFileKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
      ])
      guard values.isRegularFile == true else {
        throw PlanningError.inputUnavailable
      }
      let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize
      guard let allocated, allocated >= 0 else {
        throw PlanningError.inputUnavailable
      }
      return Int64(allocated)
    } catch let error as PlanningError {
      throw error
    } catch {
      throw PlanningError.inputUnavailable
    }
  }

  private func requiredCapacity(for sourceBytes: Int64, family: MediaFamily) -> Int64 {
    let multiplier: Int64
    switch family {
    case .audio, .image:
      multiplier = 2
    case .video:
      multiplier = 3
    }

    let (estimatedOutput, multipliedOverflow) = sourceBytes.multipliedReportingOverflow(
      by: multiplier
    )
    guard !multipliedOverflow else { return Int64.max }
    let (required, additionOverflow) = estimatedOutput.addingReportingOverflow(Self.temporaryMargin)
    return additionOverflow ? Int64.max : required
  }

  private static func importantUsageCapacity(for input: URL) throws -> Int64 {
    let values = try input.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    guard let available = values.volumeAvailableCapacityForImportantUsage else {
      throw PlanningError.inputUnavailable
    }
    return available
  }
}
