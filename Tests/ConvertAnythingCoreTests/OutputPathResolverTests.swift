import ConvertAnythingCore
import Foundation

let outputPathResolverTests: [TestCase] = [
  TestCase("output names follow the collision contract without changing source") {
    let sourceBytes = Data([1])
    let source = try fixtureFile(named: "sample.wav", bytes: sourceBytes)
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let directory = source.deletingLastPathComponent()
    try Data([9]).write(to: directory.appendingPathComponent("sample.m4a"))
    try Data([8]).write(to: directory.appendingPathComponent("sample-converted.m4a"))

    let paths = try OutputPathResolver().resolve(
      input: source,
      target: .m4a,
      jobID: UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
    )

    try expectEqual(paths.final.lastPathComponent, "sample-converted-2.m4a")
    try expectEqual(
      paths.temporary.lastPathComponent,
      ".sample.convert-anything-10000000-0000-0000-0000-000000000000.m4a"
    )
    try expectEqual(try Data(contentsOf: source), sourceBytes)
  },
  TestCase("first output uses the source stem and target extension") {
    let source = try fixtureFile(named: "holiday.photo.PNG")
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

    let paths = try OutputPathResolver().resolve(input: source, target: .avif, jobID: UUID())

    try expectEqual(paths.final.lastPathComponent, "holiday.photo.avif")
    try expectEqual(paths.final.deletingLastPathComponent(), source.deletingLastPathComponent())
  },
]
