import ConvertAnythingCore
import SwiftUI

public struct PopoverView: View {
  @ObservedObject private var model: AppViewModel
  private let onSettings: @MainActor () -> Void
  private let onQuit: @MainActor () -> Void

  public init(
    model: AppViewModel,
    onSettings: @escaping @MainActor () -> Void,
    onQuit: @escaping @MainActor () -> Void
  ) {
    self.model = model
    self.onSettings = onSettings
    self.onQuit = onQuit
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(width: 360)
    .frame(minHeight: 330, maxHeight: 520)
    .dropDestination(for: URL.self) { urls, _ in
      Task { await model.handleDrop(urls) }
      return !urls.isEmpty
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("Convert Anything")
          .font(.headline)
        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if model.snapshot.isRunning {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private var content: some View {
    if model.snapshot.jobs.isEmpty {
      VStack(spacing: 10) {
        Image(systemName: model.toolsAvailable ? "arrow.down.doc" : "exclamationmark.triangle")
          .font(.system(size: 28, weight: .light))
          .foregroundStyle(model.toolsAvailable ? Color.accentColor : .orange)
        Text(model.toolsAvailable ? "Drop media here" : "Bundled tools are missing")
          .font(.subheadline.weight(.medium))
        Text("WAV, AIFF, FLAC, CAF, M4A, MOV, MP4, MKV, WebM, JPEG, PNG, WebP, or TIFF")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, minHeight: 210)
      .padding()
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(sortedJobs) { job in
            JobRowView(job: job, model: model)
            Divider().padding(.leading, 48)
          }
        }
      }
      .frame(minHeight: 210)
    }

    if !model.admissionErrors.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(model.admissionErrors, id: \.self) { error in
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.bottom, 10)
    }
  }

  private var footer: some View {
    HStack {
      Button("Settings…", action: onSettings)
      Spacer()
      if hasFinishedJobs {
        Button("Clear") { Task { await model.clearFinishedJobs() } }
          .help("Clear finished conversions")
      }
      if let output = model.lastDrainSummary?.lastSuccessfulOutput {
        Button("Show Output") { model.reveal(output) }
      }
      Button("Quit", action: onQuit)
    }
    .buttonStyle(.borderless)
    .padding(12)
  }

  private var hasFinishedJobs: Bool {
    model.snapshot.jobs.contains { $0.state.isTerminal }
  }

  private var statusText: String {
    if !model.toolsAvailable { return "Setup required" }
    if model.snapshot.unfinishedCount > 0 {
      return "\(model.snapshot.unfinishedCount) item(s) remaining"
    }
    if let summary = model.lastDrainSummary {
      return CompletionSummaryFormatter.text(for: summary)
    }
    return "Local, private media conversion"
  }

  private var sortedJobs: [ConversionJob] {
    model.snapshot.jobs.sorted { priority($0.state) < priority($1.state) }
  }

  private func priority(_ state: ConversionJobState) -> Int {
    switch state {
    case .probing, .converting, .validating: 0
    case .queued: 1
    case .failed: 2
    case .succeeded: 3
    case .canceled: 4
    }
  }
}
