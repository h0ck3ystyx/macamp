@preconcurrency import AVFoundation
import Audio
import Contracts
import Foundation

@main
struct AudioProbe {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("AudioProbe error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else { return usage() }
        let paths = Array(arguments.dropFirst())
        switch command {
        case "inspect":
            guard !paths.isEmpty else { return usage() }
            let results = try paths.map { try NativeAudioDecoder.inspect(url: fileURL($0)) }
            if results.count == 1 { try printJSON(results[0]) } else { try printJSON(results) }
        case "decode":
            guard paths.count == 1 else { return usage() }
            let decoder = try NativeAudioDecoder(url: fileURL(paths[0]))
            let format = await decoder.format
            var frames = 0
            var peak: Float = 0
            while true {
                let chunk = try await decoder.read(maxFrames: 4_096)
                frames += chunk.frameCount
                for sample in chunk.interleavedSamples { peak = max(peak, abs(sample)) }
                if chunk.isEndOfStream { break }
            }
            try printJSONObject([
                "channelCount": format.channelCount,
                "complete": format.frameCount == Int64(frames),
                "decodedFrames": frames,
                "expectedFrames": format.frameCount.map { $0 as Any } ?? NSNull(),
                "peak": peak,
                "sampleRate": format.sampleRate,
            ])
        case "seek":
            guard paths.count == 2, let seconds = Double(paths[1]) else { return usage() }
            let decoder = try NativeAudioDecoder(url: fileURL(paths[0]))
            let format = await decoder.format
            let frame = Int64(seconds * format.sampleRate)
            try await decoder.seek(toFrame: frame)
            let chunk = try await decoder.read(maxFrames: 1_024)
            try printJSONObject(["requestedFrame": frame, "decodedFrames": chunk.frameCount, "end": chunk.isEndOfStream])
        case "boundary":
            guard paths.count == 2 else { return usage() }
            try printJSON(NativeBoundaryRenderer.render(first: fileURL(paths[0]), second: fileURL(paths[1])))
        case "play":
            guard paths.count == 1 else { return usage() }
            try await play(fileURL(paths[0]))
        case "engine-play":
            guard paths.count == 1 else { return usage() }
            try await enginePlay(fileURL(paths[0]))
        case "engine-soak":
            guard paths.count == 1 || paths.count == 2 else { return usage() }
            try await engineSoak(fileURL(paths[0]), seconds: paths.count == 2 ? Double(paths[1]) ?? 10 : 10)
        case "engine-pair":
            guard paths.count == 2 else { return usage() }
            try await enginePair(first: fileURL(paths[0]), second: fileURL(paths[1]))
        case "engine-stress":
            guard paths.count == 1 else { return usage() }
            try await engineStress(fileURL(paths[0]))
        case "engine-failure":
            guard paths.isEmpty else { return usage() }
            try await engineFailure()
        case "encode-he-aac":
            guard paths.count == 2 else { return usage() }
            try encodeHEAAC(input: fileURL(paths[0]), output: fileURL(paths[1]))
        case "eq":
            guard paths.isEmpty else { return usage() }
            try printJSON(NativeGraphProbe.equalizer())
        case "output":
            guard paths.isEmpty else { return usage() }
            try printJSON(NativeGraphProbe.output())
        case "protection":
            guard paths.isEmpty else { return usage() }
            try printJSON(NativeGraphProbe.protection())
        default:
            usage(); exit(2)
        }
    }

    private static func play(_ url: URL) async throws {
        let file = try AVAudioFile(forReading: url)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        try engine.start()
        await withCheckedContinuation { continuation in
            player.scheduleFile(file, at: nil) { @Sendable in continuation.resume() }
            player.play()
        }
        player.stop(); engine.stop()
    }

    private static func enginePlay(_ url: URL) async throws {
        let decoder = try NativeAudioDecoder(url: url)
        let engine = NativeAudioEngineClient()
        let generation = PlaybackGeneration(rawValue: 1)
        let entryID = QueueEntryID()
        var events = engine.events.makeAsyncIterator()
        try await engine.prepare(
            current: AudioTrackPreparation(entryID: entryID, generation: generation, decoder: decoder),
            next: nil
        )
        try await engine.play(generation: generation)
        while let event = await events.next() {
            switch event {
            case .ended:
                try printJSON(["result": "ended", "entryID": entryID.rawValue.uuidString])
                return
            case .failed(let failure, _): throw failure
            case .outputUnavailable:
                throw PlaybackFailure(code: .outputUnavailable, message: "Output became unavailable")
            default: continue
            }
        }
    }

    private static func engineSoak(_ url: URL, seconds: TimeInterval) async throws {
        guard seconds.isFinite, seconds > 0 else { return usage() }
        let decoder = try NativeAudioDecoder(url: url)
        let engine = NativeAudioEngineClient()
        let generation = PlaybackGeneration(rawValue: 1)
        let entryID = QueueEntryID()
        var events = engine.events.makeAsyncIterator()
        try await engine.prepare(current: AudioTrackPreparation(entryID: entryID, generation: generation, decoder: decoder), next: nil)
        await engine.setVolume(0)
        try await engine.play(generation: generation)
        while let event = await events.next() {
            switch event {
            case .position(let position, _) where position >= seconds:
                await engine.stop(generation: generation)
                try printJSONObject(["result": "passed", "seconds": position, "entryID": entryID.rawValue.uuidString])
                return
            case .ended:
                try printJSONObject(["result": "ended", "seconds": seconds, "entryID": entryID.rawValue.uuidString])
                return
            case .failed(let failure, _): throw failure
            case .outputUnavailable:
                throw PlaybackFailure(code: .outputUnavailable, message: "Output became unavailable")
            default: continue
            }
        }
    }

    private static func enginePair(first: URL, second: URL) async throws {
        let firstDecoder = try NativeAudioDecoder(url: first)
        let secondDecoder = try NativeAudioDecoder(url: second)
        let engine = NativeAudioEngineClient()
        let generation = PlaybackGeneration(rawValue: 1)
        let firstID = QueueEntryID()
        let secondID = QueueEntryID()
        var events = engine.events.makeAsyncIterator()
        try await engine.prepare(
            current: AudioTrackPreparation(entryID: firstID, generation: generation, decoder: firstDecoder),
            next: AudioTrackPreparation(entryID: secondID, generation: generation, decoder: secondDecoder)
        )
        try await engine.play(generation: generation)
        var transitioned = false
        while let event = await events.next() {
            switch event {
            case .transitioned(let entryID, _): transitioned = transitioned || entryID == secondID
            case .ended(let entryID, _) where entryID == secondID:
                try printJSONObject(["result": "ended", "transitioned": transitioned])
                return
            case .failed(let failure, _): throw failure
            case .outputUnavailable:
                throw PlaybackFailure(code: .outputUnavailable, message: "Output became unavailable")
            default: continue
            }
        }
    }

    private static func engineStress(_ url: URL) async throws {
        let decoder = try NativeAudioDecoder(url: url)
        let engine = NativeAudioEngineClient(framesPerBuffer: 1_024, maximumScheduledBuffers: 3, targetBufferDuration: 0)
        let entryID = QueueEntryID()
        let first = PlaybackGeneration(rawValue: 10)
        let sought = PlaybackGeneration(rawValue: 11)
        let restarted = PlaybackGeneration(rawValue: 12)
        var events = engine.events.makeAsyncIterator()
        try await engine.prepare(current: AudioTrackPreparation(entryID: entryID, generation: first, decoder: decoder), next: nil)
        await engine.setVolume(0.35)
        await engine.setEqualizer(EQSettings(isBypassed: false, preampGain: -3, bandGains: [0, 0, 0, 0, 3, 6, 3, 0, 0, 0]))
        try await engine.play(generation: first)
        try await engine.seek(to: 0.25, generation: sought)
        await engine.pause(generation: sought)
        try await engine.play(generation: sought)
        await engine.stop(generation: restarted)
        await engine.setEqualizer(EQSettings())
        try await engine.play(generation: restarted)
        var failureCount = 0
        while let event = await events.next() {
            switch event {
            case .ended(let endedID, let generation) where endedID == entryID && generation == restarted:
                try printJSONObject(["result": "ended", "failureEvents": failureCount, "finalGeneration": generation.rawValue])
                return
            case .failed: failureCount += 1
            case .outputUnavailable:
                throw PlaybackFailure(code: .outputUnavailable, message: "Output became unavailable")
            default: continue
            }
        }
    }

    private static func engineFailure() async throws {
        let engine = NativeAudioEngineClient()
        let generation = PlaybackGeneration(rawValue: 21)
        var events = engine.events.makeAsyncIterator()
        do {
            try await engine.prepare(
                current: AudioTrackPreparation(entryID: QueueEntryID(), generation: generation, decoder: ProbeFailingDecoder()),
                next: nil
            )
            throw PlaybackFailure(code: .unknown, message: "Failing decoder unexpectedly prepared")
        } catch {
            guard case .failed(let failure, let eventGeneration)? = await events.next() else { throw error }
            try printJSONObject(["result": "failed", "code": failure.code.rawValue, "generation": eventGeneration.rawValue])
        }
    }

    private static func encodeHEAAC(input: URL, output: URL) throws {
        let source = try AVAudioFile(forReading: input)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC_HE,
            AVSampleRateKey: source.processingFormat.sampleRate,
            AVNumberOfChannelsKey: source.processingFormat.channelCount,
            AVEncoderBitRateKey: 48_000,
        ]
        let destination = try AVAudioFile(forWriting: output, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 16_384) else {
            throw PlaybackFailure(code: .unknown, message: "Could not allocate AAC encoder buffer")
        }
        while source.framePosition < source.length {
            try source.read(into: buffer, frameCount: min(buffer.frameCapacity, AVAudioFrameCount(source.length - source.framePosition)))
            try destination.write(from: buffer)
        }
        try printJSONObject(["result": "encoded", "path": output.path])
    }

    private static func fileURL(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }
    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
    private static func printJSONObject(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    private static func usage() {
        print("Usage:\n  AudioProbe inspect <file> [file ...]\n  AudioProbe decode <file>\n  AudioProbe seek <file> <seconds>\n  AudioProbe boundary <first-file> <second-file>\n  AudioProbe play <file>\n  AudioProbe engine-play <file>\n  AudioProbe engine-soak <file> [seconds]\n  AudioProbe engine-pair <first-file> <second-file>\n  AudioProbe engine-stress <file>\n  AudioProbe engine-failure\n  AudioProbe encode-he-aac <input> <output.m4a-or-aac>\n  AudioProbe eq\n  AudioProbe protection\n  AudioProbe output")
    }
}

private actor ProbeFailingDecoder: Decoder {
    var format: AudioFormatDescription {
        AudioFormatDescription(codec: "corrupt-probe", sampleRate: 48_000, channelCount: 2, frameCount: 4_096)
    }
    func seek(toFrame frame: Int64) async throws { _ = frame }
    func read(maxFrames: Int) async throws -> PCMChunk {
        _ = maxFrames
        throw PlaybackFailure(code: .corrupt, message: "Synthetic decoder failure")
    }
}
