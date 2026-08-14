import Foundation
import OptimizeAnythingCore
import OptimizeAnythingMac

let localNotificationServiceTests: [MacTestCase] = [
  MacTestCase("completion summary includes every drain count without a full path") {
    let summary = DrainSummary(
      succeededCount: 2,
      failedCount: 1,
      canceledCount: 0,
      bytesSaved: 2_048,
      lastSuccessfulOutput: URL(fileURLWithPath: "/Users/example/media/output.m4a")
    )

    let content = LocalNotificationService.content(for: summary)

    try macExpectEqual(content.title, "Optimization finished with issues")
    try macExpectTrue(content.body.contains("2 completed"))
    try macExpectTrue(content.body.contains("1 failed"))
    try macExpectTrue(content.body.contains("0 canceled"))
    try macExpectTrue(content.body.contains("saved"))
    try macExpectTrue(!content.body.contains("/Users/example"))
    try macExpectEqual(
      content.userInfo[LocalNotificationService.outputPathUserInfoKey] as? String,
      summary.lastSuccessfulOutput?.path
    )
  }
]
