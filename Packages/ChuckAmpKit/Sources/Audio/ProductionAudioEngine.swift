@preconcurrency import AppKit
@preconcurrency import AVFoundation
import AudioToolbox
import Contracts
import Foundation

public enum EqualizerPreset: String, Codable, CaseIterable, Sendable {
    case flat, rock, pop, jazz, classical, bassBoost

    public var settings: EQSettings {
        let gains: [Double]
        switch self {
        case .flat: gains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .rock: gains = [4, 3, 2, 0, -1, 0, 2, 3, 4, 4]
        case .pop: gains = [-1, 1, 3, 4, 2, -1, -1, 2, 3, 2]
        case .jazz: gains = [3, 2, 1, 2, -1, -1, 0, 1, 3, 4]
        case .classical: gains = [3, 2, 1, 0, -1, -1, 0, 1, 3, 4]
        case .bassBoost: gains = [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        }
        return EQSettings(isBypassed: self == .flat, preampGain: 0, bandGains: gains)
    }
}

public struct OutputProtectionStatus: Codable, Equatable, Sendable {
    public let limiterEnabled: Bool
    public let requestedPositiveGainDB: Double
    public let mayBeReducingGain: Bool
    public let ceilingDBFS: Double
}

/// Native, bounded-buffer implementation of the frozen AudioEngineClient contract.
/// All graph mutation is serialized by this actor; completion callbacks only enqueue
/// actor work and never decode, allocate UI objects, or persist state.
public actor NativeAudioEngineClient: AudioEngineClient {
    public nonisolated let events: AsyncStream<AudioEngineEvent>

    private enum Lane: Sendable { case a, b }
    private enum Location: Sendable { case current, next }

    private struct TrackState: Sendable {
        var preparation: AudioTrackPreparation
        var format: AudioFormatDescription
        var lane: Lane
        var token: UUID
        var scheduledBuffers = 0
        var isFilling = false
        var reachedEnd = false
        var baseFrame: Int64 = 0
        var playedFrames: Int64 = 0
    }

    private final class ObserverBag: @unchecked Sendable {
        var defaultCenterTokens: [NSObjectProtocol] = []
        var workspaceTokens: [NSObjectProtocol] = []
        deinit {
            for token in defaultCenterTokens { NotificationCenter.default.removeObserver(token) }
            for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        }
    }

    private let continuation: AsyncStream<AudioEngineEvent>.Continuation
    private let engine = AVAudioEngine()
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()
    private let trackMixer = AVAudioMixerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: EQSettings.frequencies.count)
    private let peakLimiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    private let observerBag = ObserverBag()
    private let framesPerBuffer: Int
    private let maximumScheduledBuffers: Int

    private var current: TrackState?
    private var next: TrackState?
    private var isPlaying = false
    private var positionTask: Task<Void, Never>?
    private var equalizerRevision: UInt64 = 0
    private var equalizerSettings = EQSettings()
    private var graphReady = false

    public init(framesPerBuffer: Int = 4_096, maximumScheduledBuffers: Int = 6) {
        precondition((256...65_536).contains(framesPerBuffer))
        precondition((2...32).contains(maximumScheduledBuffers))
        let stream = AsyncStream.makeStream(of: AudioEngineEvent.self, bufferingPolicy: .bufferingNewest(256))
        self.events = stream.stream
        self.continuation = stream.continuation
        self.framesPerBuffer = framesPerBuffer
        self.maximumScheduledBuffers = maximumScheduledBuffers

        for (index, frequency) in EQSettings.frequencies.enumerated() {
            equalizer.bands[index].filterType = .parametric
            equalizer.bands[index].frequency = Float(frequency)
            equalizer.bands[index].bandwidth = 1
            equalizer.bands[index].gain = 0
            equalizer.bands[index].bypass = false
        }
        equalizer.bypass = true
        AudioUnitSetParameter(peakLimiter.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(peakLimiter.audioUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.024, 0)
        AudioUnitSetParameter(peakLimiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0, 0)
        Task { await self.finishInitialization() }
    }

    public func prepare(current preparation: AudioTrackPreparation, next nextPreparation: AudioTrackPreparation?) async throws {
        try ensureGraph()
        invalidateAllPlayback()

        let format = await preparation.decoder.format
        try validate(format)
        current = TrackState(preparation: preparation, format: format, lane: .a, token: UUID())
        try await fillCurrent()

        if let nextPreparation {
            try await installNext(nextPreparation, lane: .b)
        }
        continuation.yield(.prepared(entryID: preparation.entryID, generation: preparation.generation))
    }

    public func updateNext(_ preparation: AudioTrackPreparation?) async throws {
        guard current != nil else {
            if preparation != nil { throw PlaybackFailure(code: .cancelled, message: "Cannot stage a next track without a current track") }
            return
        }
        invalidateNext()
        guard let preparation else { return }
        guard preparation.generation.rawValue >= (current?.preparation.generation.rawValue ?? 0) else {
            throw PlaybackFailure(code: .cancelled, message: "Ignored next-track prefetch for a stale generation")
        }
        let lane: Lane = current?.lane == .a ? .b : .a
        try await installNext(preparation, lane: lane)
        if isPlaying { scheduleNextStart() }
    }

    public func play(generation: PlaybackGeneration) async throws {
        guard var current, generation.rawValue >= current.preparation.generation.rawValue else {
            throw PlaybackFailure(code: .cancelled, message: "Ignored play for a stale generation")
        }
        try ensureGraph()
        if !engine.isRunning { try engine.start() }
        current.preparation = AudioTrackPreparation(entryID: current.preparation.entryID, generation: generation, decoder: current.preparation.decoder)
        self.current = current
        node(for: current.lane).play()
        isPlaying = true
        scheduleNextStart()
        startPositionEvents(generation: generation)
    }

    public func pause(generation: PlaybackGeneration) async {
        guard let current, generation.rawValue >= current.preparation.generation.rawValue else { return }
        node(for: current.lane).pause()
        isPlaying = false
        positionTask?.cancel()
        positionTask = nil
        await rewindNextPrefetch()
        emitPosition(generation: generation)
    }

    public func stop(generation: PlaybackGeneration) async {
        guard var state = current, generation.rawValue >= state.preparation.generation.rawValue else { return }
        isPlaying = false
        positionTask?.cancel()
        positionTask = nil
        node(for: state.lane).stop()
        state.token = UUID()
        state.scheduledBuffers = 0
        state.reachedEnd = false
        state.baseFrame = 0
        state.playedFrames = 0
        state.preparation = AudioTrackPreparation(entryID: state.preparation.entryID, generation: generation, decoder: state.preparation.decoder)
        do {
            try await state.preparation.decoder.seek(toFrame: 0)
            current = state
            try await fillCurrent()
            await rewindNextPrefetch()
            continuation.yield(.position(0, generation: generation))
        } catch {
            current = state
            yieldFailure(error, generation: generation)
        }
    }

    public func seek(to time: TimeInterval, generation: PlaybackGeneration) async throws {
        guard var state = current, generation.rawValue >= state.preparation.generation.rawValue else {
            throw PlaybackFailure(code: .cancelled, message: "Ignored seek for a stale generation")
        }
        guard time.isFinite, time >= 0 else {
            throw PlaybackFailure(code: .unsupported, message: "Seek time must be finite and nonnegative")
        }
        let requested = Int64(time * state.format.sampleRate)
        let frame = min(requested, state.format.frameCount ?? requested)
        let resume = isPlaying
        isPlaying = false
        positionTask?.cancel()
        node(for: state.lane).stop()
        state.token = UUID()
        state.scheduledBuffers = 0
        state.reachedEnd = false
        state.baseFrame = frame
        state.playedFrames = 0
        state.preparation = AudioTrackPreparation(entryID: state.preparation.entryID, generation: generation, decoder: state.preparation.decoder)
        try await state.preparation.decoder.seek(toFrame: frame)
        current = state
        try await fillCurrent()
        await rewindNextPrefetch()
        continuation.yield(.position(Double(frame) / state.format.sampleRate, generation: generation))
        if resume { try await play(generation: generation) }
    }

    public func setVolume(_ volume: Double) async {
        engine.mainMixerNode.outputVolume = Float(min(max(volume, 0), 1))
    }

    public func setEqualizer(_ settings: EQSettings) async {
        equalizerRevision &+= 1
        let revision = equalizerRevision
        let old = equalizerSettings
        equalizerSettings = settings
        let steps = 12
        for step in 1...steps {
            guard revision == equalizerRevision else { return }
            let fraction = Double(step) / Double(steps)
            equalizer.globalGain = Float(interpolate(old.preampGain, settings.preampGain, fraction: fraction).clamped(to: -12...12))
            for index in 0..<min(equalizer.bands.count, settings.bandGains.count) {
                let gain = interpolate(old.bandGains[index], settings.bandGains[index], fraction: fraction)
                equalizer.bands[index].gain = Float(gain.clamped(to: -12...12))
            }
            if step < steps { try? await Task.sleep(for: .milliseconds(3)) }
        }
        equalizer.bypass = settings.isBypassed
    }

    /// Describes when the post-EQ peak limiter may be active. The system peak
    /// limiter does not expose sample-accurate gain reduction, so this is a
    /// conservative UI indicator based on requested positive gain.
    public func outputProtectionStatus() -> OutputProtectionStatus {
        let highestBand = equalizerSettings.bandGains.max() ?? 0
        let positiveGain = equalizerSettings.isBypassed ? 0 : max(0, equalizerSettings.preampGain + highestBand)
        return OutputProtectionStatus(
            limiterEnabled: true,
            requestedPositiveGainDB: positiveGain,
            mayBeReducingGain: positiveGain > 0,
            ceilingDBFS: 0
        )
    }

    private func finishInitialization() {
        let configuration = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in Task { await self?.handleUnsafeOutputChange() } }
        observerBag.defaultCenterTokens.append(configuration)
        let center = NSWorkspace.shared.notificationCenter
        observerBag.workspaceTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.handleUnsafeOutputChange() }
        })
    }

    private func ensureGraph() throws {
        guard !graphReady else { return }
        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(trackMixer)
        engine.attach(equalizer)
        engine.attach(peakLimiter)
        engine.connect(playerA, to: trackMixer, format: nil)
        engine.connect(playerB, to: trackMixer, format: nil)
        engine.connect(trackMixer, to: equalizer, format: nil)
        engine.connect(equalizer, to: peakLimiter, format: nil)
        engine.connect(peakLimiter, to: engine.mainMixerNode, format: nil)
        engine.prepare()
        graphReady = true
    }

    private func installNext(_ preparation: AudioTrackPreparation, lane: Lane) async throws {
        let format = await preparation.decoder.format
        try validate(format)
        next = TrackState(preparation: preparation, format: format, lane: lane, token: UUID())
        try await fillNext()
    }

    private func validate(_ format: AudioFormatDescription) throws {
        guard format.sampleRate > 0, format.sampleRate.isFinite else {
            throw PlaybackFailure(code: .corrupt, message: "Audio has an invalid sample rate")
        }
        guard (1...2).contains(format.channelCount) else {
            throw PlaybackFailure(code: .unsupported, message: "Only mono and stereo audio are supported")
        }
    }

    private func fillCurrent() async throws {
        guard let state = current else { return }
        try await fill(token: state.token)
    }

    private func fillNext() async throws {
        guard let state = next else { return }
        try await fill(token: state.token)
    }

    private func fill(token: UUID) async throws {
        let location: Location
        if current?.token == token { location = .current }
        else if next?.token == token { location = .next }
        else { return }

        var state = location == .current ? current! : next!
        guard !state.isFilling, !state.reachedEnd else { return }
        state.isFilling = true
        assign(state, to: location)
        defer {
            if var final = trackState(for: token) {
                final.isFilling = false
                assign(final, matching: token)
            }
        }

        while state.scheduledBuffers < maximumScheduledBuffers, !state.reachedEnd {
            let chunk: PCMChunk
            do { chunk = try await state.preparation.decoder.read(maxFrames: framesPerBuffer) }
            catch {
                assign(state, to: location)
                yieldFailure(error, generation: state.preparation.generation)
                throw error
            }
            guard stateFor(location)?.token == token else { return }
            if chunk.frameCount == 0 {
                state.reachedEnd = true
                assign(state, to: location)
                handleEmptyEnd(state)
                break
            }
            let buffer = try makeBuffer(chunk: chunk, format: state.format)
            state.scheduledBuffers += 1
            state.reachedEnd = chunk.isEndOfStream
            assign(state, to: location)
            node(for: state.lane).scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { await self?.bufferCompleted(token: token, frames: chunk.frameCount, wasEnd: chunk.isEndOfStream) }
            }
        }
    }

    private func bufferCompleted(token: UUID, frames: Int, wasEnd: Bool) async {
        if var state = current, state.token == token {
            state.scheduledBuffers = max(0, state.scheduledBuffers - 1)
            state.playedFrames += Int64(frames)
            current = state
            if wasEnd { finishCurrent(state) }
            else { try? await fillCurrent() }
            return
        }
        if var state = next, state.token == token {
            state.scheduledBuffers = max(0, state.scheduledBuffers - 1)
            state.playedFrames += Int64(frames)
            next = state
            if wasEnd, current?.token != token { return }
            try? await fillNext()
        }
    }

    private func finishCurrent(_ state: TrackState) {
        if var promoted = next {
            next = nil
            promoted.baseFrame = 0
            promoted.playedFrames = max(0, promoted.playedFrames)
            current = promoted
            continuation.yield(.transitioned(entryID: promoted.preparation.entryID, generation: promoted.preparation.generation))
            if promoted.reachedEnd, promoted.scheduledBuffers == 0 {
                isPlaying = false
                positionTask?.cancel()
                continuation.yield(.ended(entryID: promoted.preparation.entryID, generation: promoted.preparation.generation))
            } else if isPlaying {
                startPositionEvents(generation: promoted.preparation.generation)
            }
        } else {
            isPlaying = false
            positionTask?.cancel()
            continuation.yield(.ended(entryID: state.preparation.entryID, generation: state.preparation.generation))
        }
    }

    private func handleEmptyEnd(_ state: TrackState) {
        if current?.token == state.token { finishCurrent(state) }
    }

    private func makeBuffer(chunk: PCMChunk, format: AudioFormatDescription) throws -> AVAudioPCMBuffer {
        guard chunk.interleavedSamples.count == chunk.frameCount * format.channelCount,
              let audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: AVAudioChannelCount(format.channelCount),
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(chunk.frameCount)),
              let channels = buffer.floatChannelData else {
            throw PlaybackFailure(code: .corrupt, message: "Decoder returned malformed PCM")
        }
        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
        for frame in 0..<chunk.frameCount {
            for channel in 0..<format.channelCount {
                channels[channel][frame] = chunk.interleavedSamples[frame * format.channelCount + channel]
            }
        }
        return buffer
    }

    private func scheduleNextStart() {
        guard isPlaying, let current, let next else { return }
        let currentNode = node(for: current.lane)
        let nextNode = node(for: next.lane)
        guard !nextNode.isPlaying else { return }
        let length = current.format.frameCount ?? currentPositionFrame(current)
        let remainingFrames = max(0, length - currentPositionFrame(current))
        let delay = Double(remainingFrames) / current.format.sampleRate
        let hostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay)
        nextNode.play(at: AVAudioTime(hostTime: hostTime))
        _ = currentNode
    }

    private func rewindNextPrefetch() async {
        guard var state = next else { return }
        node(for: state.lane).stop()
        state.token = UUID()
        state.scheduledBuffers = 0
        state.reachedEnd = false
        state.baseFrame = 0
        state.playedFrames = 0
        do {
            try await state.preparation.decoder.seek(toFrame: 0)
            next = state
            try await fillNext()
        } catch {
            next = nil
            yieldFailure(error, generation: state.preparation.generation)
        }
    }

    private func startPositionEvents(generation: PlaybackGeneration) {
        positionTask?.cancel()
        positionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                await self?.positionTick(generation: generation)
            }
        }
    }

    private func positionTick(generation: PlaybackGeneration) {
        guard isPlaying, current?.preparation.generation == generation else { return }
        emitPosition(generation: generation)
    }

    private func emitPosition(generation: PlaybackGeneration) {
        guard let current else { return }
        let seconds = Double(currentPositionFrame(current)) / current.format.sampleRate
        continuation.yield(.position(seconds, generation: generation))
    }

    private func currentPositionFrame(_ state: TrackState) -> Int64 {
        let completed = state.baseFrame + state.playedFrames
        let player = node(for: state.lane)
        guard let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime),
              playerTime.sampleTime >= 0 else { return completed }
        return max(completed, state.baseFrame + playerTime.sampleTime)
    }

    private func handleUnsafeOutputChange() async {
        guard let state = current else { return }
        let generation = state.preparation.generation
        let frame = currentPositionFrame(state)
        isPlaying = false
        positionTask?.cancel()
        node(for: state.lane).stop()
        node(for: state.lane == .a ? .b : .a).stop()
        var reset = state
        reset.token = UUID()
        reset.scheduledBuffers = 0
        reset.reachedEnd = false
        reset.baseFrame = frame
        reset.playedFrames = 0
        do {
            try await reset.preparation.decoder.seek(toFrame: frame)
            current = reset
            try await fillCurrent()
            await rewindNextPrefetch()
        } catch {
            current = reset
            yieldFailure(error, generation: generation)
        }
        continuation.yield(.outputUnavailable(generation: generation))
    }

    private func invalidateAllPlayback() {
        isPlaying = false
        positionTask?.cancel()
        positionTask = nil
        playerA.stop(); playerB.stop()
        current = nil; next = nil
    }

    private func invalidateNext() {
        guard let next else { return }
        node(for: next.lane).stop()
        self.next = nil
    }

    private func node(for lane: Lane) -> AVAudioPlayerNode { lane == .a ? playerA : playerB }

    private func trackState(for token: UUID) -> TrackState? {
        if current?.token == token { return current }
        if next?.token == token { return next }
        return nil
    }

    private func stateFor(_ location: Location) -> TrackState? {
        location == .current ? current : next
    }

    private func assign(_ state: TrackState, matching token: UUID) {
        if current?.token == token { current = state }
        else if next?.token == token { next = state }
    }

    private func assign(_ state: TrackState, to location: Location) {
        if location == .current { current = state } else { next = state }
    }

    private func yieldFailure(_ error: Error, generation: PlaybackGeneration) {
        let failure: PlaybackFailure
        if let typed = error as? PlaybackFailure { failure = typed }
        else if error is CancellationError { failure = PlaybackFailure(code: .cancelled, message: "Audio operation was cancelled") }
        else if let native = error as? NativeAudioError {
            let code: PlaybackFailure.Code
            switch native {
            case .unsupportedChannelCount, .unsupportedChainedStream: code = .unsupported
            case .corruptFile, .seekOutOfRange, .invalidFrameRequest: code = .corrupt
            case .couldNotCreateBuffer, .renderFailed: code = .unknown
            }
            failure = PlaybackFailure(code: code, message: native.localizedDescription)
        } else {
            failure = PlaybackFailure(code: .corrupt, message: error.localizedDescription)
        }
        continuation.yield(.failed(failure, generation: generation))
    }

    private func interpolate(_ start: Double, _ end: Double, fraction: Double) -> Double {
        start + (end - start) * fraction
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
