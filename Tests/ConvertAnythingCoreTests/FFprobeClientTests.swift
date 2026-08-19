import ConvertAnythingCore
import ConvertAnythingTestSupport
import Foundation

let ffprobeClientTests: [TestCase] = [
  TestCase("probe maps exact JSON fields to media info") {
    let executor = FakeCommandExecutor.probeJSON(
      #"{"format":{"format_name":"image2","duration":"2.5"},"streams":[{"codec_type":"video","codec_name":"png","pix_fmt":"rgba","width":320,"height":200},{"codec_type":"audio","codec_name":"pcm_s16le","channels":2}]}"#
    )
    let input = URL(fileURLWithPath: "/tmp/image with $dollars.png")
    let commandID = UUID(uuidString: "30000000-0000-0000-0000-000000000000")!
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: executor
    )

    let info = try await client.probe(input, commandID: commandID)

    try expectEqual(info.containerNames, ["image2"])
    try expectEqual(info.durationSeconds, 2.5)
    try expectEqual(info.videoCodec, "png")
    try expectEqual(info.audioCodec, "pcm_s16le")
    try expectEqual(info.width, 320)
    try expectEqual(info.height, 200)
    try expectEqual(info.channelCount, 2)
    try expectTrue(info.hasAlpha)
    let requests = await executor.requests
    try expectEqual(requests.count, 1)
    try expectEqual(requests[0].id, commandID)
    try expectEqual(requests[0].executable.path, "/tools/ffprobe")
    try expectEqual(
      requests[0].arguments,
      ["-v", "error", "-show_format", "-show_streams", "-of", "json", input.path]
    )
  },
  TestCase("probe recognizes AVIF auxiliary alpha and rotation metadata") {
    let executor = FakeCommandExecutor.probeJSON(
      #"{"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","tags":{"major_brand":"avif","compatible_brands":"avifmif1miafMA1A"}},"streams":[{"codec_type":"video","codec_name":"av1","pix_fmt":"yuv420p","width":96,"height":64,"side_data_list":[{"rotation":90}]},{"codec_type":"video","codec_name":"av1","pix_fmt":"gray"}]}"#
    )
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: executor
    )

    let info = try await client.probe(URL(fileURLWithPath: "/tmp/alpha.avif"), commandID: UUID())

    try expectTrue(info.hasAlpha)
    try expectTrue(info.containerNames.contains("avif"))
    try expectEqual(info.rotationDegrees, 90)
  },
  TestCase("probe rejects malformed JSON rather than inventing defaults") {
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: FakeCommandExecutor.probeJSON("not-json")
    )

    do {
      _ = try await client.probe(URL(fileURLWithPath: "/tmp/bad.mov"), commandID: UUID())
      throw TestFailure(description: "Expected invalid probe response")
    } catch let error as MediaProbeError {
      try expectEqual(error, .invalidResponse)
    }
  },
]
