import AppKit
import ConvertAnythingCore
import Foundation

@MainActor
public final class ApplicationController {
  public let model: AppViewModel

  private let notificationService: any NotificationServing
  private let settingsWindowController: SettingsWindowController
  private let statusBarController: StatusBarController

  public init(bundle: Bundle = .main, fileManager: FileManager = .default) {
    let settingsURL = Self.settingsURL(fileManager: fileManager)
    let settingsStore = MappingStore(fileURL: settingsURL)
    let executor = FoundationCommandExecutor()
    let ffmpeg = bundle.url(forResource: "ffmpeg", withExtension: nil)
    let ffprobe = bundle.url(forResource: "ffprobe", withExtension: nil)
    let toolsAvailable = [ffmpeg, ffprobe].allSatisfy { url in
      guard let url else { return false }
      return fileManager.isExecutableFile(atPath: url.path)
    }
    let ffmpegURL = ffmpeg ?? URL(fileURLWithPath: "/missing/ffmpeg")
    let ffprobeURL = ffprobe ?? URL(fileURLWithPath: "/missing/ffprobe")
    let probe = FFprobeClient(executable: ffprobeURL, executor: executor)
    let runner = FFmpegRunner(executable: ffmpegURL, executor: executor)
    let conversion = ConversionService(probe: probe, runner: runner, fileManager: fileManager)
    let queue = ConversionQueue(converter: conversion)
    if bundle.bundleIdentifier == nil {
      notificationService = UnavailableNotificationService()
    } else {
      notificationService = LocalNotificationService()
    }
    model = AppViewModel(
      dependencies: ViewModelDependencies(
        settings: settingsStore,
        admission: DropAdmissionService(),
        planner: ConversionPlanner(),
        queue: queue,
        notifications: notificationService,
        finder: FinderService()
      ),
      toolsAvailable: toolsAvailable
    )
    settingsWindowController = SettingsWindowController(model: model)
    statusBarController = StatusBarController(
      model: model,
      onSettings: { [weak settingsWindowController] in settingsWindowController?.show() },
      onQuit: { NSApplication.shared.terminate(nil) }
    )
    Task { await model.loadSettings() }
  }

  public func ingest(_ urls: [URL]) async {
    await model.handleDrop(urls)
  }

  private static func settingsURL(fileManager: FileManager) -> URL {
    let applicationSupport =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return
      applicationSupport
      .appendingPathComponent("com.channprj.convert-anything", isDirectory: true)
      .appendingPathComponent("settings.json")
  }
}

private struct UnavailableNotificationService: NotificationServing {
  func authorizationStatus() async -> NotificationAuthorizationStatus {
    .denied
  }

  func requestAuthorizationIfNeeded() async {}

  func deliver(_ summary: DrainSummary) async throws {}
}
