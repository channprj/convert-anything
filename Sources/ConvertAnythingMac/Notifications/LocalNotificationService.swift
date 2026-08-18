import AppKit
import ConvertAnythingCore
import Foundation
import UserNotifications

public final class LocalNotificationService: NSObject, NotificationServing,
  UNUserNotificationCenterDelegate, @unchecked Sendable
{
  public static let outputPathUserInfoKey = "outputPath"

  private let center: UNUserNotificationCenter

  public init(center: UNUserNotificationCenter = .current()) {
    self.center = center
    super.init()
    center.delegate = self
  }

  public func authorizationStatus() async -> NotificationAuthorizationStatus {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return .authorized
    case .denied:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .denied
    }
  }

  public func requestAuthorizationIfNeeded() async {
    guard await authorizationStatus() == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  public func deliver(_ summary: DrainSummary) async throws {
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: Self.content(for: summary),
      trigger: nil
    )
    try await center.add(request)
  }

  public static func content(for summary: DrainSummary) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    let hasIssues = summary.failedCount > 0 || summary.canceledCount > 0
    content.title = hasIssues ? "Conversion finished with issues" : "Conversion complete"

    content.body = CompletionSummaryFormatter.text(for: summary)
    content.sound = .default
    if let output = summary.lastSuccessfulOutput {
      content.userInfo[Self.outputPathUserInfoKey] = output.path
    }
    return content
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard
      let path = response.notification.request.content.userInfo[Self.outputPathUserInfoKey]
        as? String
    else {
      return
    }
    await MainActor.run {
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
  }
}
