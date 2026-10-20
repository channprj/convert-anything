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
      [
        "-v", "error", "-show_format", "-show_streams", "-show_stream_groups", "-of", "json",
        input.path,
      ]
    )
  },
  TestCase("probe recognizes AVIF auxiliary alpha and rotation metadata") {
    let executor = FakeCommandExecutor.probeJSON(
      #"{"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","tags":{"major_brand":"avif","compatible_brands":"avifmif1miafMA1A"}},"streams":[{"codec_type":"video","codec_name":"av1","pix_fmt":"yuv420p","width":96,"height":64,"side_data_list":[{"rotation":90}]},{"codec_type":"video","codec_name":"av1","pix_fmt":"gray","width":96,"height":64}]}"#
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
  TestCase("probe recognizes HEIC auxiliary alpha") {
    let executor = FakeCommandExecutor.probeJSON(
      #"{"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","tags":{"major_brand":"mif1","compatible_brands":"mif1heicmiaf"}},"streams":[{"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":96,"height":64},{"codec_type":"video","codec_name":"hevc","pix_fmt":"gray","width":96,"height":64}]}"#
    )
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: executor
    )

    let info = try await client.probe(URL(fileURLWithPath: "/tmp/alpha.heic"), commandID: UUID())

    try expectTrue(info.hasAlpha)
    try expectEqual(info.auxiliaryAlphaVideoStreamIndex, 1)
    try expectTrue(info.containerNames.contains("heic"))
  },
  TestCase("probe identifies the exact HEIC auxiliary alpha stream") {
    let executor = FakeCommandExecutor.probeJSON(
      #"{"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","tags":{"major_brand":"heic","compatible_brands":"mif1heicmiaf"}},"streams":[{"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":96,"height":64},{"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":48,"height":32},{"codec_type":"video","codec_name":"hevc","pix_fmt":"gray","width":96,"height":64}]}"#
    )
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: executor
    )

    let info = try await client.probe(
      URL(fileURLWithPath: "/tmp/alpha-with-thumbnail.heic"), commandID: UUID())

    try expectTrue(info.hasAlpha)
    try expectEqual(info.auxiliaryAlphaVideoStreamIndex, 2)
  },
  TestCase("probe does not mistake a multi-image HEIC collection for alpha") {
    let executor = FakeCommandExecutor.probeJSON(
      #"{"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","tags":{"major_brand":"heic","compatible_brands":"mif1heicmiaf"}},"streams":[{"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":96,"height":64},{"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":96,"height":64}]}"#
    )
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: executor
    )

    let info = try await client.probe(
      URL(fileURLWithPath: "/tmp/collection.heic"), commandID: UUID())

    try expectTrue(!info.hasAlpha)
    try expectEqual(info.auxiliaryAlphaVideoStreamIndex, nil)
    try expectTrue(info.containerNames.contains("heic"))
  },
  TestCase("probe uses a HEIC tile grid instead of its first tile") {
    let executor = FakeCommandExecutor.probeJSON(
      """
      {"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","tags":{"major_brand":"heic","compatible_brands":"mif1heic"}},\
      "streams":[{"index":0,"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":512,"height":512},\
      {"index":1,"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":512,"height":512},\
      {"index":2,"codec_type":"video","codec_name":"hevc","pix_fmt":"gray","width":512,"height":512}],\
      "stream_groups":[{"type":"Tile Grid","disposition":{"default":1},"components":[{"coded_width":1024,\
      "coded_height":1024,"horizontal_offset":0,"vertical_offset":0,"width":1024,"height":768,\
      "subcomponents":[{"stream_index":0,"tile_horizontal_offset":0,"tile_vertical_offset":0},\
      {"stream_index":1,"tile_horizontal_offset":512,"tile_vertical_offset":0}]}],\
      "streams":[{"index":0,"pix_fmt":"yuv420p"},{"index":1,"pix_fmt":"yuv420p"}]},\
      {"type":"Tile Grid","disposition":{"default":0},"components":[{"coded_width":1024,"coded_height":1024,\
      "horizontal_offset":0,"vertical_offset":0,"width":1024,"height":768,\
      "subcomponents":[{"stream_index":0,"tile_horizontal_offset":0,"tile_vertical_offset":0}]}],\
      "streams":[{"index":2,"pix_fmt":"gray"}]}]}
      """
    )
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: executor
    )

    let info = try await client.probe(
      URL(fileURLWithPath: "/tmp/convert-anything-missing-grid.heic"), commandID: UUID())

    try expectEqual(info.width, 1024)
    try expectEqual(info.height, 768)
    try expectTrue(info.hasAlpha)
    try expectEqual(info.auxiliaryAlphaVideoStreamIndex, nil)
    try expectEqual(info.heicOrientation, 1)
    try expectEqual(
      info.heicColorGrid?.tiles.map(\.streamIndex),
      [0, 1]
    )
    try expectEqual(info.heicColorGrid?.width, 1024)
    try expectEqual(info.heicColorGrid?.height, 768)
    try expectEqual(info.heicAlphaGrid?.tiles.map(\.streamIndex), [2])
  },
  TestCase("probe does not treat a HEIC tile-sized gray stream as alpha") {
    let executor = FakeCommandExecutor.probeJSON(
      """
      {"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","tags":{"major_brand":"heic","compatible_brands":"mif1heic"}},\
      "streams":[{"index":0,"codec_type":"video","codec_name":"hevc","pix_fmt":"yuv420p","width":512,"height":512},\
      {"index":1,"codec_type":"video","codec_name":"hevc","pix_fmt":"gray","width":512,"height":512}],\
      "stream_groups":[{"type":"Tile Grid","disposition":{"default":1},"components":[{"coded_width":1024,\
      "coded_height":512,"horizontal_offset":0,"vertical_offset":0,"width":1000,"height":500,\
      "subcomponents":[{"stream_index":0,"tile_horizontal_offset":0,"tile_vertical_offset":0}]}],\
      "streams":[{"index":0,"pix_fmt":"yuv420p"}]}]}
      """
    )
    let client = FFprobeClient(
      executable: URL(fileURLWithPath: "/tools/ffprobe"),
      executor: executor
    )

    let info = try await client.probe(
      URL(fileURLWithPath: "/tmp/convert-anything-missing-color.heic"), commandID: UUID())

    try expectTrue(!info.hasAlpha)
    try expectEqual(info.auxiliaryAlphaVideoStreamIndex, nil)
    try expectEqual(info.width, 1000)
    try expectEqual(info.height, 500)
    try expectEqual(info.heicAlphaGrid, nil)
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
