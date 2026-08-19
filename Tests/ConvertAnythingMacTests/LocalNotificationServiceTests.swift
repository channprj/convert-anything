import ConvertAnythingCore
import ConvertAnythingMac
import ConvertAnythingTestSupport
import Foundation

let localNotificationServiceTests: [TestCase] = [
  TestCase("completion summary includes every drain count without a full path") {
    let summary = DrainSummary(
      succeededCount: 2,
      failedCount: 1,
      canceledCount: 0,
      bytesSaved: 2_048,
      lastSuccessfulOutput: URL(fileURLWithPath: "/Users/example/media/output.m4a")
    )

    let content = LocalNotificationService.content(for: summary)

    try expectEqual(content.title, "Conversion finished with issues")
    try expectTrue(content.body.contains("2 completed"))
    try expectTrue(content.body.contains("1 failed"))
    try expectTrue(content.body.contains("0 canceled"))
    try expectTrue(content.body.contains("saved"))
    try expectTrue(!content.body.contains("/Users/example"))
    try expectEqual(
      content.userInfo[LocalNotificationService.outputPathUserInfoKey] as? String,
      summary.lastSuccessfulOutput?.path
    )
  }
]
