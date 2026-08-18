import Foundation

public struct DrainSummary: Equatable, Sendable {
  public let succeededCount: Int
  public let failedCount: Int
  public let canceledCount: Int
  public let bytesSaved: Int64
  public let lastSuccessfulOutput: URL?

  public init(
    succeededCount: Int,
    failedCount: Int,
    canceledCount: Int,
    bytesSaved: Int64,
    lastSuccessfulOutput: URL?
  ) {
    self.succeededCount = succeededCount
    self.failedCount = failedCount
    self.canceledCount = canceledCount
    self.bytesSaved = bytesSaved
    self.lastSuccessfulOutput = lastSuccessfulOutput
  }
}
