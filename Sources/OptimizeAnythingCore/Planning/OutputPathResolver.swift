import Foundation

public struct OutputPathResolver: Sendable {
  public init() {}

  public func resolve(input: URL, target: TargetFormat, jobID: UUID) throws -> OutputPaths {
    let directory = input.deletingLastPathComponent()
    let stem = input.deletingPathExtension().lastPathComponent
    let targetExtension = target.rawValue

    var final = directory.appendingPathComponent("\(stem).\(targetExtension)")
    if FileManager.default.fileExists(atPath: final.path) {
      final = directory.appendingPathComponent("\(stem)-optimized.\(targetExtension)")
    }

    var collisionIndex = 2
    while FileManager.default.fileExists(atPath: final.path) {
      final = directory.appendingPathComponent(
        "\(stem)-optimized-\(collisionIndex).\(targetExtension)")
      collisionIndex += 1
    }

    let temporary = directory.appendingPathComponent(
      ".\(stem).optimize-anything-\(jobID.uuidString.lowercased()).\(targetExtension)"
    )
    return OutputPaths(final: final, temporary: temporary)
  }
}
