import ConvertAnythingCore
import Foundation

public enum CompletionSummaryFormatter {
  public static func text(for summary: DrainSummary) -> String {
    let byteFormatter = ByteCountFormatter()
    byteFormatter.countStyle = .file
    return [
      "\(summary.succeededCount) completed",
      "\(summary.failedCount) failed",
      "\(summary.canceledCount) canceled",
      "\(byteFormatter.string(fromByteCount: summary.bytesSaved)) saved",
    ].joined(separator: " · ")
  }
}
