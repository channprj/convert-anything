import Foundation

public struct CommandRequest: Sendable {
  public let id: UUID
  public let executable: URL
  public let arguments: [String]

  public init(id: UUID, executable: URL, arguments: [String]) {
    self.id = id
    self.executable = executable
    self.arguments = arguments
  }
}

public struct CommandResult: Equatable, Sendable {
  public let terminationStatus: Int32
  public let standardOutput: Data
  public let standardError: Data

  public init(terminationStatus: Int32, standardOutput: Data, standardError: Data) {
    self.terminationStatus = terminationStatus
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

extension CommandResult {
  /// Last line of stderr, used as the human-facing failure detail.
  func lastStandardErrorLine(fallback: String) -> String {
    String(decoding: standardError, as: UTF8.self)
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .last ?? fallback
  }
}

public enum CommandExecutorError: Error, Equatable, Sendable {
  case launchFailed(String)
}

public protocol CommandExecuting: Sendable {
  func execute(
    _ request: CommandRequest,
    onStandardOutputLine: @escaping @Sendable (String) -> Void
  ) async throws -> CommandResult
  func terminate(commandID: UUID) async
}

public actor FoundationCommandExecutor: CommandExecuting {
  private var processes: [UUID: Process] = [:]

  public init() {}

  public func execute(
    _ request: CommandRequest,
    onStandardOutputLine: @escaping @Sendable (String) -> Void
  ) async throws -> CommandResult {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let output = StreamAccumulator(onLine: onStandardOutputLine)
    let errors = StreamAccumulator()

    process.executableURL = request.executable
    process.arguments = request.arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      output.append(handle.availableData)
    }
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      errors.append(handle.availableData)
    }

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let completion = CommandContinuation(continuation)
        process.terminationHandler = { terminatedProcess in
          outputPipe.fileHandleForReading.readabilityHandler = nil
          errorPipe.fileHandleForReading.readabilityHandler = nil
          output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
          errors.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
          let result = CommandResult(
            terminationStatus: terminatedProcess.terminationStatus,
            standardOutput: output.finish(),
            standardError: errors.finish()
          )
          Task {
            await self.processDidExit(request.id)
            completion.resume(returning: result)
          }
        }

        processes[request.id] = process
        do {
          try process.run()
        } catch {
          outputPipe.fileHandleForReading.readabilityHandler = nil
          errorPipe.fileHandleForReading.readabilityHandler = nil
          processes.removeValue(forKey: request.id)
          completion.resume(throwing: CommandExecutorError.launchFailed(error.localizedDescription))
        }
      }
    } onCancel: {
      Task { await self.terminate(commandID: request.id) }
    }
  }

  public func terminate(commandID: UUID) async {
    guard let process = processes[commandID], process.isRunning else { return }
    process.terminate()
  }

  private func processDidExit(_ commandID: UUID) {
    processes.removeValue(forKey: commandID)
  }
}

private final class CommandContinuation: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<CommandResult, Error>?

  init(_ continuation: CheckedContinuation<CommandResult, Error>) {
    self.continuation = continuation
  }

  func resume(returning result: CommandResult) {
    take()?.resume(returning: result)
  }

  func resume(throwing error: any Error) {
    take()?.resume(throwing: error)
  }

  private func take() -> CheckedContinuation<CommandResult, Error>? {
    lock.withLock {
      defer { continuation = nil }
      return continuation
    }
  }
}

private final class StreamAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private let onLine: (@Sendable (String) -> Void)?
  private var data = Data()
  private var pending = Data()

  init(onLine: (@Sendable (String) -> Void)? = nil) {
    self.onLine = onLine
  }

  func append(_ chunk: Data) {
    guard !chunk.isEmpty else { return }
    let lines: [String] = lock.withLock {
      data.append(chunk)
      guard onLine != nil else { return [] }
      pending.append(chunk)
      return consumeCompleteLines()
    }
    for line in lines {
      onLine?(line)
    }
  }

  func finish() -> Data {
    let result: (Data, String?) = lock.withLock {
      let trailingLine = pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
      pending.removeAll(keepingCapacity: false)
      return (data, trailingLine)
    }
    if let trailingLine = result.1 {
      onLine?(trailingLine)
    }
    return result.0
  }

  private func consumeCompleteLines() -> [String] {
    var lines: [String] = []
    while let newlineIndex = pending.firstIndex(of: 0x0A) {
      var line = pending[..<newlineIndex]
      if line.last == 0x0D {
        line = line.dropLast()
      }
      lines.append(String(decoding: line, as: UTF8.self))
      pending.removeSubrange(...newlineIndex)
    }
    return lines
  }
}
