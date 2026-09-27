@preconcurrency import AVFoundation
import AudioToolbox
import Contracts
import Foundation

public enum AudioModule {
    public static let isPrototypeImplemented = true
}

public enum NativeAudioError: Error, LocalizedError, Sendable {
    case corruptFile(String)
    case invalidFrameRequest(Int)
    case unsupportedChannelCount(Int)
    case unsupportedChainedStream(Int)
    case seekOutOfRange(Int64)
    case couldNotCreateBuffer
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .corruptFile(let reason): "Unreadable or corrupt audio: \(reason)"
        case .invalidFrameRequest(let count): "Invalid PCM frame request: \(count)"
        case .unsupportedChannelCount(let count): "MacAmp supports mono and stereo; file has \(count) channels"
        case .unsupportedChainedStream(let count): "Chained Ogg streams are not supported (found \(count) logical streams)"
        case .seekOutOfRange(let frame): "Seek frame is out of range: \(frame)"
        case .couldNotCreateBuffer: "Could not allocate a PCM buffer"
        case .renderFailed(let reason): "Offline audio render failed: \(reason)"
        }
    }
}

public struct NativeAudioInspection: Codable, Equatable, Sendable {
    public let path: String
    public let fileType: String?
    public let codec: String
    public let sampleRate: Double
    public let channelCount: Int
    public let decodedFrameCount: Int64
    public let durationSeconds: Double
    public let encoderDelayFrames: Int64?
    public let trailingPaddingFrames: Int64?
}

private final class ExtAudioFileHandle: @unchecked Sendable {
    let raw: ExtAudioFileRef
    init(_ raw: ExtAudioFileRef) { self.raw = raw }
    deinit { ExtAudioFileDispose(raw) }
}

/// A bounded, seekable decoder backed by codecs exposed through AVFoundation.
/// Multichannel input is rejected until the product has an explicit downmix policy.
public actor NativeAudioDecoder: Decoder {
    private let file: ExtAudioFileHandle
    private let description: AudioFormatDescription
    private var currentFrame: Int64 = 0

    public init(url: URL) throws {
        if let streamCount = try Self.oggLogicalStreamCount(url: url), streamCount > 1 {
            throw NativeAudioError.unsupportedChainedStream(streamCount)
        }
        var opened: ExtAudioFileRef?
        let openStatus = ExtAudioFileOpenURL(url as CFURL, &opened)
        guard openStatus == noErr else { throw NativeAudioError.corruptFile("OSStatus \(openStatus)") }
        guard let opened else { throw NativeAudioError.renderFailed("ExtAudioFileOpenURL returned no file") }
        let handle = ExtAudioFileHandle(opened)
        var sourceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(ExtAudioFileGetProperty(handle.raw, kExtAudioFileProperty_FileDataFormat, &formatSize, &sourceFormat), operation: "read source format")
        let channels = Int(sourceFormat.mChannelsPerFrame)
        guard (1...2).contains(channels) else { throw NativeAudioError.unsupportedChannelCount(channels) }
        var length: Int64 = 0
        var lengthSize = UInt32(MemoryLayout<Int64>.size)
        try Self.check(ExtAudioFileGetProperty(handle.raw, kExtAudioFileProperty_FileLengthFrames, &lengthSize, &length), operation: "read frame length")
        guard let requestedFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.mSampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else { throw NativeAudioError.renderFailed("could not describe the Float32 client format") }
        var clientFormat = requestedFormat.streamDescription.pointee
        try Self.check(ExtAudioFileSetProperty(handle.raw, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat), operation: "set Float32 client format")
        let trimming = Self.readPacketTable(url: url)
        self.file = handle
        self.description = AudioFormatDescription(
            codec: Self.fourCC(sourceFormat.mFormatID),
            sampleRate: sourceFormat.mSampleRate,
            channelCount: channels,
            frameCount: length,
            encoderDelayFrames: trimming?.delay,
            trailingPaddingFrames: trimming?.padding
        )
    }

    public var format: AudioFormatDescription { description }

    public func seek(toFrame frame: Int64) throws {
        guard frame >= 0, frame <= description.frameCount ?? 0 else { throw NativeAudioError.seekOutOfRange(frame) }
        try Self.check(ExtAudioFileSeek(file.raw, frame), operation: "seek")
        currentFrame = frame
    }

    public func read(maxFrames: Int) throws -> PCMChunk {
        guard maxFrames > 0, maxFrames <= 1_048_576 else { throw NativeAudioError.invalidFrameRequest(maxFrames) }
        let length = description.frameCount ?? 0
        if currentFrame >= length {
            return PCMChunk(interleavedSamples: [], frameCount: 0, isEndOfStream: true)
        }
        let requested = UInt32(min(Int64(maxFrames), length - currentFrame))
        let channels = description.channelCount
        var samples = [Float](repeating: 0, count: Int(requested) * channels)
        var framesRead = requested
        let status = samples.withUnsafeMutableBytes { bytes -> OSStatus in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(channels),
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
            )
            return ExtAudioFileRead(file.raw, &framesRead, &list)
        }
        try Self.check(status, operation: "decode")
        samples.removeLast(samples.count - Int(framesRead) * channels)
        currentFrame += Int64(framesRead)
        return PCMChunk(interleavedSamples: samples, frameCount: Int(framesRead), isEndOfStream: currentFrame >= length || framesRead == 0)
    }

    public static func inspect(url: URL) throws -> NativeAudioInspection {
        if let streamCount = try oggLogicalStreamCount(url: url), streamCount > 1 {
            throw NativeAudioError.unsupportedChainedStream(streamCount)
        }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw NativeAudioError.corruptFile(error.localizedDescription) }
        let channels = Int(file.processingFormat.channelCount)
        guard (1...2).contains(channels) else { throw NativeAudioError.unsupportedChannelCount(channels) }
        let trimming = readPacketTable(url: url)
        let sampleRate = file.processingFormat.sampleRate
        return NativeAudioInspection(
            path: url.path,
            fileType: readFileType(url: url),
            codec: codecName(file.fileFormat.settings),
            sampleRate: sampleRate,
            channelCount: channels,
            decodedFrameCount: file.length,
            durationSeconds: sampleRate > 0 ? Double(file.length) / sampleRate : 0,
            encoderDelayFrames: trimming?.delay,
            trailingPaddingFrames: trimming?.padding
        )
    }

    private static func codecName(_ settings: [String: Any]) -> String {
        guard let formatID = settings[AVFormatIDKey] as? UInt32 else { return "unknown" }
        let chars = [UInt8((formatID >> 24) & 0xff), UInt8((formatID >> 16) & 0xff), UInt8((formatID >> 8) & 0xff), UInt8(formatID & 0xff)]
        if chars.allSatisfy({ $0 >= 32 && $0 < 127 }) { return String(bytes: chars, encoding: .ascii) ?? String(formatID) }
        return String(formatID)
    }

    private static func fourCC(_ value: UInt32) -> String {
        let chars = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        return chars.allSatisfy({ $0 >= 32 && $0 < 127 }) ? (String(bytes: chars, encoding: .ascii) ?? String(value)) : String(value)
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else { throw NativeAudioError.renderFailed("\(operation) failed with OSStatus \(status)") }
    }

    private static func readPacketTable(url: URL) -> (delay: Int64, padding: Int64)? {
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile) == noErr, let audioFile else { return nil }
        defer { AudioFileClose(audioFile) }
        var info = AudioFilePacketTableInfo()
        var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
        guard AudioFileGetProperty(audioFile, kAudioFilePropertyPacketTableInfo, &size, &info) == noErr else { return nil }
        return (Int64(info.mPrimingFrames), Int64(info.mRemainderFrames))
    }

    private static func readFileType(url: URL) -> String? {
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile) == noErr, let audioFile else { return nil }
        defer { AudioFileClose(audioFile) }
        var type: AudioFileTypeID = 0
        var size = UInt32(MemoryLayout<AudioFileTypeID>.size)
        guard AudioFileGetProperty(audioFile, kAudioFilePropertyFileFormat, &size, &type) == noErr else { return nil }
        return fourCC(type)
    }

    /// Returns nil for non-Ogg input. The parser walks page headers with constant
    /// memory so chained streams are rejected before a decoder silently plays only
    /// the first logical bitstream.
    private static func oggLogicalStreamCount(url: URL) throws -> Int? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let prefix = try handle.read(upToCount: 4), prefix == Data("OggS".utf8) else { return nil }
        try handle.seek(toOffset: 0)
        var serials = Set<UInt32>()
        while true {
            guard let header = try handle.read(upToCount: 27), !header.isEmpty else { break }
            guard header.count == 27, header.prefix(4) == Data("OggS".utf8), header[4] == 0 else {
                throw NativeAudioError.corruptFile("invalid Ogg page header")
            }
            let serial = UInt32(header[14]) | UInt32(header[15]) << 8 | UInt32(header[16]) << 16 | UInt32(header[17]) << 24
            if header[5] & 0x02 != 0 { serials.insert(serial) }
            let segmentCount = Int(header[26])
            guard let lacing = try handle.read(upToCount: segmentCount), lacing.count == segmentCount else {
                throw NativeAudioError.corruptFile("truncated Ogg segment table")
            }
            let bodySize = lacing.reduce(0) { $0 + Int($1) }
            let next = try handle.offset() + UInt64(bodySize)
            try handle.seek(toOffset: next)
        }
        return serials.count
    }
}

public struct BoundaryRenderResult: Codable, Equatable, Sendable {
    public let firstDecodedFrames: Int64
    public let secondDecodedFrames: Int64
    public let renderedFrames: Int64
    public let boundarySampleDelta: Float
    public let peakNearBoundary: Float
}

/// Exercises sample-time scheduling of two files in the intended AVAudioEngine graph.
public enum NativeBoundaryRenderer {
    public static func render(first: URL, second: URL) throws -> BoundaryRenderResult {
        let firstFile = try AVAudioFile(forReading: first)
        let secondFile = try AVAudioFile(forReading: second)
        let format = firstFile.processingFormat
        guard format.sampleRate == secondFile.processingFormat.sampleRate,
              format.channelCount == secondFile.processingFormat.channelCount else {
            throw NativeAudioError.renderFailed("files must have matching sample rates and channel counts")
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        player.scheduleFile(firstFile, at: AVAudioTime(sampleTime: 0, atRate: format.sampleRate))
        player.scheduleFile(secondFile, at: AVAudioTime(sampleTime: firstFile.length, atRate: format.sampleRate))
        try engine.start()
        player.play(at: AVAudioTime(sampleTime: 0, atRate: format.sampleRate))

        let targetFrames = firstFile.length + secondFile.length
        let boundary = firstFile.length
        var rendered: Int64 = 0
        var before: Float = 0
        var after: Float = 0
        var peak: Float = 0
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096) else {
            throw NativeAudioError.couldNotCreateBuffer
        }
        while rendered < targetFrames {
            let count = AVAudioFrameCount(min(Int64(buffer.frameCapacity), targetFrames - rendered))
            let status = try engine.renderOffline(count, to: buffer)
            guard status == .success || status == .insufficientDataFromInputNode else {
                throw NativeAudioError.renderFailed("AVAudioEngine status \(status.rawValue)")
            }
            guard let data = buffer.floatChannelData else { throw NativeAudioError.renderFailed("render did not return Float32 PCM") }
            let produced = Int64(buffer.frameLength)
            for offset in 0..<Int(produced) {
                let absolute = rendered + Int64(offset)
                let sample = data[0][offset]
                if absolute == boundary - 1 { before = sample }
                if absolute == boundary { after = sample }
                if absolute >= boundary - 16, absolute < boundary + 16 { peak = max(peak, abs(sample)) }
            }
            rendered += produced
            if produced == 0 { break }
        }
        player.stop()
        engine.stop()
        return BoundaryRenderResult(firstDecodedFrames: firstFile.length, secondDecodedFrames: secondFile.length, renderedFrames: rendered, boundarySampleDelta: abs(after - before), peakNearBoundary: peak)
    }
}

public struct EqualizerProbeResult: Codable, Equatable, Sendable {
    public let bypassRMS: Float
    public let boostedRMS: Float
    public let measuredGainDB: Float
}

public struct OutputProbeResult: Codable, Equatable, Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let engineStarted: Bool
}

public struct ProtectionProbeResult: Codable, Equatable, Sendable {
    public let inputPeak: Float
    public let requestedGainDB: Float
    public let unprotectedPredictedPeak: Float
    public let protectedPeak: Float
}

public enum NativeGraphProbe {
    public static func equalizer() throws -> EqualizerProbeResult {
        let bypass = try renderTone(eqGain: 0)
        let boosted = try renderTone(eqGain: 12)
        return EqualizerProbeResult(
            bypassRMS: bypass,
            boostedRMS: boosted,
            measuredGainDB: 20 * log10(boosted / bypass)
        )
    }

    public static func output() throws -> OutputProbeResult {
        let engine = AVAudioEngine()
        let format = engine.outputNode.outputFormat(forBus: 0)
        try engine.start()
        let started = engine.isRunning
        engine.stop()
        return OutputProbeResult(sampleRate: format.sampleRate, channelCount: Int(format.channelCount), engineStarted: started)
    }

    public static func protection() throws -> ProtectionProbeResult {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let frameCount: AVAudioFrameCount = 48_000
        guard let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = source.floatChannelData else { throw NativeAudioError.couldNotCreateBuffer }
        source.frameLength = frameCount
        let inputPeak: Float = 0.9
        let requestedGain: Float = 12
        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(2 * Double.pi * 1_000 * Double(frame) / 48_000)) * inputPeak
            data[0][frame] = sample; data[1][frame] = sample
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.globalGain = requestedGain
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        engine.attach(player); engine.attach(eq); engine.attach(limiter)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        player.scheduleBuffer(source)
        try engine.start(); player.play(at: AVAudioTime(sampleTime: 0, atRate: 48_000))
        guard let rendered = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096) else {
            throw NativeAudioError.couldNotCreateBuffer
        }
        var peak: Float = 0
        var remaining = Int64(frameCount)
        while remaining > 0 {
            let count = AVAudioFrameCount(min(Int64(rendered.frameCapacity), remaining))
            let status = try engine.renderOffline(count, to: rendered)
            guard status == .success, let channels = rendered.floatChannelData else {
                throw NativeAudioError.renderFailed("protection render status \(status.rawValue)")
            }
            for frame in 0..<Int(rendered.frameLength) { peak = max(peak, abs(channels[0][frame])) }
            remaining -= Int64(rendered.frameLength)
        }
        player.stop(); engine.stop()
        return ProtectionProbeResult(
            inputPeak: inputPeak,
            requestedGainDB: requestedGain,
            unprotectedPredictedPeak: inputPeak * pow(10, requestedGain / 20),
            protectedPeak: peak
        )
    }

    private static func renderTone(eqGain: Float) throws -> Float {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let frameCount: AVAudioFrameCount = 24_000
        guard let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = source.floatChannelData else { throw NativeAudioError.couldNotCreateBuffer }
        source.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(2 * Double.pi * 1_000 * Double(frame) / 48_000) * 0.1)
            data[0][frame] = sample
            data[1][frame] = sample
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.bands[0].filterType = .parametric
        eq.bands[0].frequency = 1_000
        eq.bands[0].bandwidth = 1
        eq.bands[0].gain = eqGain
        eq.bands[0].bypass = false
        engine.attach(player); engine.attach(eq)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        player.scheduleBuffer(source)
        try engine.start(); player.play(at: AVAudioTime(sampleTime: 0, atRate: 48_000))
        guard let rendered = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096) else {
            throw NativeAudioError.couldNotCreateBuffer
        }
        var sum: Double = 0
        var samples = 0
        var remaining = Int64(frameCount)
        while remaining > 0 {
            let count = AVAudioFrameCount(min(Int64(rendered.frameCapacity), remaining))
            let status = try engine.renderOffline(count, to: rendered)
            guard status == .success, let channels = rendered.floatChannelData else {
                throw NativeAudioError.renderFailed("EQ render status \(status.rawValue)")
            }
            for frame in 0..<Int(rendered.frameLength) {
                let value = Double(channels[0][frame])
                sum += value * value
                samples += 1
            }
            remaining -= Int64(rendered.frameLength)
        }
        player.stop(); engine.stop()
        return Float(sqrt(sum / Double(samples)))
    }
}
