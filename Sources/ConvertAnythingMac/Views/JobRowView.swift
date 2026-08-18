import ConvertAnythingCore
import SwiftUI

public struct JobRowView: View {
  public let job: ConversionJob
  @ObservedObject private var model: AppViewModel

  public init(job: ConversionJob, model: AppViewModel) {
    self.job = job
    self.model = model
  }

  public var body: some View {
    HStack(spacing: 10) {
      Image(systemName: iconName)
        .frame(width: 24)
        .foregroundStyle(iconColor)
      VStack(alignment: .leading, spacing: 4) {
        Text(job.plan.input.lastPathComponent)
          .lineLimit(1)
        Text(stateText)
          .font(.caption)
          .foregroundStyle(.secondary)
        if case .converting(let progress) = job.state {
          ProgressView(value: progress)
            .progressViewStyle(.linear)
        }
      }
      Spacer(minLength: 6)
      actions
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var actions: some View {
    switch job.state {
    case .probing, .converting, .validating:
      Button("Cancel") { Task { await model.cancel(jobID: job.id) } }
        .buttonStyle(.borderless)
    case .failed:
      VStack(alignment: .trailing, spacing: 4) {
        Button("Retry") { Task { await model.retry(job: job) } }
        Button("Show Source") { model.reveal(job.plan.input) }
        removeButton
      }
      .buttonStyle(.borderless)
    case .succeeded(let output, _):
      HStack(spacing: 8) {
        Button("Show Output") { model.reveal(output) }
        removeButton
      }
      .buttonStyle(.borderless)
    case .canceled:
      removeButton
        .buttonStyle(.borderless)
    case .queued:
      EmptyView()
    }
  }

  private var removeButton: some View {
    Button {
      Task { await model.remove(jobID: job.id) }
    } label: {
      Image(systemName: "xmark")
    }
    .help("Remove from history")
  }

  private var stateText: String {
    switch job.state {
    case .queued: "Queued"
    case .probing: "Inspecting media"
    case .converting(let progress): "Converting · \(Int(progress * 100))%"
    case .validating: "Validating output"
    case .succeeded(_, let bytes):
      "Complete · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    case .failed(let failure): failure.message
    case .canceled: "Canceled"
    }
  }

  private var iconName: String {
    switch job.state {
    case .queued: "clock"
    case .probing, .converting, .validating: "arrow.triangle.2.circlepath"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "exclamationmark.circle.fill"
    case .canceled: "xmark.circle"
    }
  }

  private var iconColor: Color {
    switch job.state {
    case .succeeded: .green
    case .failed: .red
    case .canceled: .secondary
    case .queued, .probing, .converting, .validating: .accentColor
    }
  }
}
