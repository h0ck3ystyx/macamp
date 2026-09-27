@testable import Audio
import Contracts
import Foundation
import Testing

@Test func audioTargetLoads() {
    #expect(AudioModule.isPrototypeImplemented)
}

@Test func waveDecodeIsBoundedSeekableAndReachesEnd() async throws {
    let url = try makeWave(frameCount: 4_800, sampleRate: 48_000)
    defer { try? FileManager.default.removeItem(at: url) }
    let decoder = try NativeAudioDecoder(url: url)
    let format = await decoder.format
    #expect(format.sampleRate == 48_000)
    #expect(format.channelCount == 1)
    #expect(format.frameCount == 4_800)
    let first = try await decoder.read(maxFrames: 257)
    #expect(first.frameCount == 257)
    #expect(!first.isEndOfStream)
    try await decoder.seek(toFrame: 4_700)
    let last = try await decoder.read(maxFrames: 512)
    #expect(last.frameCount == 100)
    #expect(last.isEndOfStream)
}

@Test func flacFallbackDecodesAndSeeksWithoutCoreAudioConversion() async throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/Fixtures/Audio/tone-44k.flac")
    let decoder = try NativeAudioDecoder(url: url)
    let format = await decoder.format
    #expect(format.codec == "flac")
    #expect(format.sampleRate == 44_100)
    #expect(format.channelCount == 2)
    #expect(format.frameCount == 88_200)
    let first = try await decoder.read(maxFrames: 4_096)
    #expect(first.frameCount == 4_096)
    #expect(first.interleavedSamples.count == 8_192)
    try await decoder.seek(toFrame: 87_500)
    let last = try await decoder.read(maxFrames: 4_096)
    #expect(last.frameCount == 700)
    #expect(last.isEndOfStream)
}

@Test func flacFallbackRetainsMonoStereoPolicy() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/Fixtures/Audio/multichannel-5_1.flac")
    #expect(throws: NativeAudioError.self) { try NativeAudioDecoder(url: url) }
}

@Test func flacFallbackAcceptsLeadingID3Metadata() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let source = root.appendingPathComponent("Tests/Fixtures/Audio/tone-44k.flac")
    let tagged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("flac")
    var data = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    data.append(try Data(contentsOf: source))
    try data.write(to: tagged)
    defer { try? FileManager.default.removeItem(at: tagged) }
    let decoder = try NativeAudioDecoder(url: tagged)
    let first = try await decoder.read(maxFrames: 4_096)
    #expect(first.frameCount == 4_096)
}

@Test func mp3FallbackDecodesAndSeeksID3TaggedAudio() async throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/Fixtures/Audio/tone-vbr-id3v23.mp3")
    let decoder = try NativeAudioDecoder(url: url)
    let format = await decoder.format
    #expect(format.codec == "mp3")
    #expect(format.sampleRate == 44_100)
    #expect(format.channelCount == 2)
    #expect(format.frameCount == 88_200)
    let first = try await decoder.read(maxFrames: 4_096)
    #expect(first.frameCount == 4_096)
    try await decoder.seek(toFrame: 87_500)
    let last = try await decoder.read(maxFrames: 4_096)
    #expect(last.frameCount == 700)
    #expect(last.isEndOfStream)
}

@Test func rejectsOutOfRangeSeekAndUnboundedRead() async throws {
    let url = try makeWave(frameCount: 100, sampleRate: 44_100)
    defer { try? FileManager.default.removeItem(at: url) }
    let decoder = try NativeAudioDecoder(url: url)
    await #expect(throws: NativeAudioError.self) { try await decoder.seek(toFrame: -1) }
    await #expect(throws: NativeAudioError.self) { try await decoder.read(maxFrames: 1_048_577) }
}

@Test func equalizerPresetsAreCompleteAndWithinSupportedRange() {
    #expect(EqualizerPreset.allCases.count >= 5)
    for preset in EqualizerPreset.allCases {
        #expect(preset.settings.bandGains.count == EQSettings.frequencies.count)
        #expect(preset.settings.bandGains.allSatisfy { (-12...12).contains($0) })
    }
}

@Test func bufferingPolicyKeepsHighRateAudioAheadOfPlayback() {
    let policy = PlaybackBufferingPolicy(minimumFramesPerBuffer: 4_096, maximumScheduledBuffers: 32, targetBufferDuration: 0.25)
    #expect(policy.framesPerBuffer(sampleRate: 44_100) == 11_025)
    #expect(policy.framesPerBuffer(sampleRate: 192_000) == 48_000)
    #expect(policy.queuedDuration(sampleRate: 44_100) == 8)
    #expect(policy.queuedDuration(sampleRate: 192_000) == 8)
}

@Test func contentInspectionRejectsAnExtensionThatContradictsThePayload() throws {
    let wave = try makeWave(frameCount: 128, sampleRate: 44_100)
    let disguised = wave.deletingPathExtension().appendingPathExtension("mp3")
    try FileManager.default.moveItem(at: wave, to: disguised)
    defer { try? FileManager.default.removeItem(at: disguised) }
    #expect(throws: NativeAudioError.self) { try NativeAudioDecoder.inspect(url: disguised) }
}

@Test func rejectsMultichannelRatherThanApplyingImplicitDownmix() async throws {
    let url = try makeWave(frameCount: 64, sampleRate: 48_000, channelCount: 6)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: NativeAudioError.self) { try NativeAudioDecoder(url: url) }
}

@Test func rejectsChainedOggBeforeNativeDecoderSilentlyStopsAtFirstStream() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("opus")
    try makeEmptyOggPage(serial: 1) .write(to: url)
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: makeEmptyOggPage(serial: 2))
    try handle.close()
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: NativeAudioError.self) { try NativeAudioDecoder(url: url) }
}

@Test func decoderPreservesLeadingAndTrailingMusicalSilence() async throws {
    let url = try makeWave(frameCount: 1_000, sampleRate: 1_000, silentPrefix: 100, silentSuffix: 150)
    defer { try? FileManager.default.removeItem(at: url) }
    let decoder = try NativeAudioDecoder(url: url)
    let chunk = try await decoder.read(maxFrames: 1_000)
    #expect(chunk.interleavedSamples.prefix(100).allSatisfy { $0 == 0 })
    #expect(chunk.interleavedSamples.suffix(150).allSatisfy { $0 == 0 })
}

@Test(.disabled("Requires an AudioComponent host; exercised by AudioProbe boundary outside the package-test sandbox"))
func schedulesTwoLosslessTracksOnOneTimeline() throws {
    let first = try makeWave(frameCount: 2_205, sampleRate: 44_100, phaseFrame: 0)
    let second = try makeWave(frameCount: 2_205, sampleRate: 44_100, phaseFrame: 2_205)
    defer {
        try? FileManager.default.removeItem(at: first)
        try? FileManager.default.removeItem(at: second)
    }
    let result = try NativeBoundaryRenderer.render(first: first, second: second)
    #expect(result.renderedFrames == 4_410)
    #expect(result.boundarySampleDelta < 0.04)
    #expect(result.peakNearBoundary > 0.1)
}

@Test(.disabled("Requires a serial AudioComponent host; covered by AudioProbe engine-stress outside Swift Testing's parallel sandbox"))
func productionEngineBoundsPrefetchAndRejectsStaleCommands() async throws {
    let decoder = RecordingDecoder(frameCount: 100_000)
    let entry = QueueEntryID()
    let generation = PlaybackGeneration(rawValue: 8)
    let engine = NativeAudioEngineClient(framesPerBuffer: 1_024, maximumScheduledBuffers: 3, targetBufferDuration: 0)
    var events = engine.events.makeAsyncIterator()
    try await engine.prepare(
        current: AudioTrackPreparation(entryID: entry, generation: generation, decoder: decoder),
        next: nil
    )
    #expect(await events.next() == .prepared(entryID: entry, generation: generation))
    #expect(await decoder.readRequests == [1_024, 1_024, 1_024])
    await #expect(throws: PlaybackFailure.self) {
        try await engine.play(generation: PlaybackGeneration(rawValue: 7))
    }
}

@Test(.disabled("Requires a serial AudioComponent host; covered by AudioProbe engine-stress outside Swift Testing's parallel sandbox"))
func productionEngineSeekInvalidatesBufferedWorkAndUsesNewGeneration() async throws {
    let decoder = RecordingDecoder(frameCount: 96_000)
    let entry = QueueEntryID()
    let engine = NativeAudioEngineClient(framesPerBuffer: 2_048, maximumScheduledBuffers: 2, targetBufferDuration: 0)
    let initial = PlaybackGeneration(rawValue: 1)
    let sought = PlaybackGeneration(rawValue: 2)
    var events = engine.events.makeAsyncIterator()
    try await engine.prepare(current: AudioTrackPreparation(entryID: entry, generation: initial, decoder: decoder), next: nil)
    _ = await events.next()
    try await engine.seek(to: 1.25, generation: sought)
    #expect(await decoder.seekFrames == [60_000])
    #expect(await events.next() == .position(1.25, generation: sought))
}

@Test(.disabled("Requires a serial AudioComponent host; covered by AudioProbe engine-pair outside Swift Testing's parallel sandbox"))
func replacingNextCancelsItsBoundedPrefetchWithoutReadingFurther() async throws {
    let current = RecordingDecoder(frameCount: 480_000)
    let discarded = RecordingDecoder(frameCount: 480_000)
    let replacement = RecordingDecoder(frameCount: 480_000)
    let generation = PlaybackGeneration(rawValue: 4)
    let engine = NativeAudioEngineClient(framesPerBuffer: 1_024, maximumScheduledBuffers: 2, targetBufferDuration: 0)
    try await engine.prepare(
        current: AudioTrackPreparation(entryID: QueueEntryID(), generation: generation, decoder: current),
        next: AudioTrackPreparation(entryID: QueueEntryID(), generation: generation, decoder: discarded)
    )
    #expect(await discarded.readRequests.count == 2)
    try await engine.updateNext(AudioTrackPreparation(entryID: QueueEntryID(), generation: generation, decoder: replacement))
    #expect(await discarded.readRequests.count == 2)
    #expect(await replacement.readRequests.count == 2)
}

@Test(.disabled("Requires a serial AudioComponent host; compiled here and run through the external production-engine probe"))
func decoderFailureIsTypedAndPublished() async throws {
    let decoder = RecordingDecoder(frameCount: 1, failure: PlaybackFailure(code: .corrupt, message: "fixture is corrupt"))
    let generation = PlaybackGeneration(rawValue: 3)
    let engine = NativeAudioEngineClient()
    var events = engine.events.makeAsyncIterator()
    await #expect(throws: PlaybackFailure.self) {
        try await engine.prepare(current: AudioTrackPreparation(entryID: QueueEntryID(), generation: generation, decoder: decoder), next: nil)
    }
    #expect(await events.next() == .failed(PlaybackFailure(code: .corrupt, message: "fixture is corrupt"), generation: generation))
}

private actor RecordingDecoder: Decoder {
    let description: AudioFormatDescription
    let failure: PlaybackFailure?
    var readRequests: [Int] = []
    var seekFrames: [Int64] = []
    var position: Int64 = 0

    init(frameCount: Int64, sampleRate: Double = 48_000, channels: Int = 2, failure: PlaybackFailure? = nil) {
        self.description = AudioFormatDescription(codec: "test", sampleRate: sampleRate, channelCount: channels, frameCount: frameCount)
        self.failure = failure
    }

    var format: AudioFormatDescription { description }

    func seek(toFrame frame: Int64) async throws {
        seekFrames.append(frame)
        position = frame
    }

    func read(maxFrames: Int) async throws -> PCMChunk {
        if let failure { throw failure }
        readRequests.append(maxFrames)
        let count = Int(min(Int64(maxFrames), max(0, (description.frameCount ?? 0) - position)))
        position += Int64(count)
        return PCMChunk(
            interleavedSamples: Array(repeating: 0.01, count: count * description.channelCount),
            frameCount: count,
            isEndOfStream: position >= description.frameCount ?? 0
        )
    }
}

private func makeWave(
    frameCount: Int,
    sampleRate: Int,
    phaseFrame: Int = 0,
    channelCount: Int = 1,
    silentPrefix: Int = 0,
    silentSuffix: Int = 0
) throws -> URL {
    var samples = [Int16]()
    samples.reserveCapacity(frameCount * channelCount)
    for index in 0..<frameCount {
        let phase = 2 * Double.pi * 440 * Double(index + phaseFrame) / Double(sampleRate)
        let sample: Int16 = index < silentPrefix || index >= frameCount - silentSuffix ? 0 : Int16(sin(phase) * 16_000)
        for _ in 0..<channelCount { samples.append(sample) }
    }
    let dataBytes = UInt32(samples.count * MemoryLayout<Int16>.size)
    var data = Data()
    func append<T>(_ value: T) { var little = value; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
    data.append(contentsOf: "RIFF".utf8); append(UInt32(36) + dataBytes)
    data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16)); append(UInt16(1)); append(UInt16(channelCount))
    append(UInt32(sampleRate)); append(UInt32(sampleRate * 2 * channelCount)); append(UInt16(2 * channelCount)); append(UInt16(16))
    data.append(contentsOf: "data".utf8); append(dataBytes)
    samples.withUnsafeBytes { data.append(contentsOf: $0) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
    try data.write(to: url)
    return url
}

private func makeEmptyOggPage(serial: UInt32) -> Data {
    var data = Data("OggS".utf8)
    data.append(0) // version
    data.append(0x02) // beginning of stream
    data.append(contentsOf: Array(repeating: 0, count: 8)) // granule position
    data.append(UInt8(serial & 0xff)); data.append(UInt8((serial >> 8) & 0xff))
    data.append(UInt8((serial >> 16) & 0xff)); data.append(UInt8((serial >> 24) & 0xff))
    data.append(contentsOf: Array(repeating: 0, count: 8)) // sequence + checksum
    data.append(0) // no segments
    return data
}
