import Audio
import Contracts
import Foundation
import Library

public enum MacIntegrationModule {
    public static let isPrototypeImplemented = true
}

public protocol PlaybackURLImporting: Sendable {
    func importURLs(_ urls: [URL]) async -> FileImportResult
}

extension FileImportService: PlaybackURLImporting {}

public typealias PlaybackDecoderFactory = @Sendable (URL) async throws -> any Decoder

/// The process-wide state machine joining queue, file access, decoding, output, and
/// durable session state. Commands and engine callbacks are serialized by this actor.
public actor ProductionPlaybackCoordinator: PlaybackCoordinator {
    public nonisolated let snapshots: AsyncStream<PlaybackSnapshot>
    public nonisolated let notices: AsyncStream<String>
    public nonisolated let visualizationFeatures: AsyncStream<VisualizationFeatures>

    private struct PreparedTrack: Sendable {
        let entryID: QueueEntryID
        let generation: PlaybackGeneration
        let lease: any FileAccessLease
    }

    private let continuation: AsyncStream<PlaybackSnapshot>.Continuation
    private let noticeContinuation: AsyncStream<String>.Continuation
    private let queue: any QueueStore
    private let importer: any PlaybackURLImporting
    private let access: any FileAccessService
    private let engine: any AudioEngineClient
    private let sessions: any SessionStore
    private let decoderFactory: PlaybackDecoderFactory
    private var value: PlaybackSnapshot
    private var sessionTemplate: SessionState
    private var generationCounter: UInt64 = 0
    private var lastPersistedPosition: TimeInterval
    private var current: PreparedTrack?
    private var stagedNext: PreparedTrack?
    private var automaticFailureAttempts = Set<QueueEntryID>()
    private var lastNotice: String?
    private var commandIsRunning = false
    private var commandWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        queue: any QueueStore,
        importer: any PlaybackURLImporting,
        access: any FileAccessService,
        engine: any AudioEngineClient,
        sessions: any SessionStore,
        restoredSession: SessionState? = nil,
        decoderFactory: @escaping PlaybackDecoderFactory
    ) {
        let stream = AsyncStream.makeStream(of: PlaybackSnapshot.self, bufferingPolicy: .bufferingNewest(64))
        let noticeStream = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(16))
        snapshots = stream.stream
        notices = noticeStream.stream
        visualizationFeatures = engine.visualizationFeatures
        continuation = stream.continuation
        noticeContinuation = noticeStream.continuation
        self.queue = queue
        self.importer = importer
        self.access = access
        self.engine = engine
        self.sessions = sessions
        self.decoderFactory = decoderFactory
        sessionTemplate = restoredSession ?? SessionState()
        value = restoredSession.map(SessionRestoration.playbackSnapshot(from:)) ?? PlaybackSnapshot()
        lastPersistedPosition = value.position
        continuation.yield(value)
        let events = engine.events
        Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.receive(event)
            }
        }
    }

    deinit {
        continuation.finish()
        noticeContinuation.finish()
    }

    /// Loads durable state before constructing the queue, preserving entry identities.
    /// Restored playback is published paused and acquires audio resources only on Play.
    public static func makeProduction(sessionStore: any SessionStore) async throws -> ProductionPlaybackCoordinator {
        let restored = try await sessionStore.load()
        let queueSnapshot = restored.map(SessionRestoration.queueSnapshot(from:)) ?? QueueSnapshot()
        let access = SecurityScopedFileAccessService()
        return ProductionPlaybackCoordinator(
            queue: ProductionQueueStore(snapshot: queueSnapshot),
            importer: FileImportService(access: access),
            access: access,
            engine: NativeAudioEngineClient(),
            sessions: sessionStore,
            restoredSession: restored,
            decoderFactory: { try NativeAudioDecoder(url: $0) }
        )
    }

    public func send(_ command: PlayerCommand) async {
        await beginCommand()
        defer { finishCommand() }
        await execute(command)
    }

    /// Actor methods may interleave whenever they await decoder or engine work. Keep
    /// user and media-key commands in arrival order so a seek cannot be overtaken by
    /// Pause/Play or by a later seek using a newer playback generation.
    private func beginCommand() async {
        guard commandIsRunning else {
            commandIsRunning = true
            return
        }
        await withCheckedContinuation { commandWaiters.append($0) }
    }

    private func finishCommand() {
        guard !commandWaiters.isEmpty else {
            commandIsRunning = false
            return
        }
        commandWaiters.removeFirst().resume()
    }

    private func execute(_ command: PlayerCommand) async {
        switch command {
        case .open(let urls): await open(urls)
        case .append(let urls): await append(urls)
        case .play: await play()
        case .pause: await pause()
        case .stop: await stop()
        case .seek(let time): await seek(to: time)
        case .previous:
            if value.position > 3, current != nil { await seek(to: 0) }
            else { await traverse(.backward, cause: .manual, shouldPlay: true) }
        case .next: await traverse(.forward, cause: .manual, shouldPlay: true)
        case .setVolume(let volume):
            guard volume.isFinite else { return }
            value.volume = min(max(volume, 0), 1)
            await engine.setVolume(value.volume)
            publish(); await persist()
        case .setEqualizer(let settings):
            value.equalizer = settings
            await engine.setEqualizer(settings)
            publish(); await persist()
        case .select, .remove, .move, .setShuffle, .setRepeat:
            await mutateQueue(command)
        }
    }

    /// Returns the queue state paired with this coordinator. UI should use this
    /// accessor instead of retaining a second queue implementation.
    public func queueSnapshot() async -> QueueSnapshot {
        await queue.snapshot()
    }

    public func clearQueue() async {
        let entryIDs = await queue.snapshot().entries.map(\.id)
        guard !entryIDs.isEmpty else { return }
        await mutateQueue(.remove(entryIDs))
    }

    public func setVisualizationActive(_ active: Bool) async {
        await engine.setVisualizationActive(active)
    }

    public func visualizationSettings() -> VisualizationSettings { sessionTemplate.visualization }

    public func updateVisualizationSettings(_ settings: VisualizationSettings) async {
        sessionTemplate.visualization = settings
        await persist()
    }

    @discardableResult
    public func undoLastQueueMutation() async -> Bool {
        guard await queue.undoLastMutation() else { return false }
        let snapshot = await queue.snapshot()
        if let currentID = value.currentEntryID,
           !snapshot.entries.contains(where: { $0.id == currentID }) {
            await releaseAllTracks(stoppingEngine: true)
            value.currentEntryID = nil
            value.position = 0
            value.duration = nil
            value.state = snapshot.entries.isEmpty ? .idle : .stopped
        } else {
            await restageNext()
        }
        publish()
        await persist()
        return true
    }

    public func updatePresentationState(skinID: String? = nil, windowLayout: WindowLayout? = nil) async {
        if let skinID { sessionTemplate.skinID = skinID }
        if let windowLayout { sessionTemplate.windowLayout = windowLayout }
        await persist()
    }

    public func openTracks(_ tracks: [TrackReference]) async {
        guard !tracks.isEmpty else { return }
        await releaseAllTracks(stoppingEngine: true)
        await queue.replace(with: tracks)
        value.currentEntryID = nil
        value.position = 0
        value.duration = nil
        await traverse(.forward, cause: .manual, shouldPlay: true)
    }

    /// Refreshes a stale security-scoped bookmark without changing stable track or
    /// queue-entry identities. A currently loaded item is prepared again at its
    /// prior position so the new access lease is used immediately.
    public func reauthorize(trackID: TrackID, at url: URL) async throws {
        let snapshot = await queue.snapshot()
        guard let track = snapshot.tracks[trackID] else {
            throw PlaybackFailure(code: .inaccessible, message: "The selected track is no longer in the queue")
        }
        let refreshed = try await access.reauthorize(track, at: url)
        try await queue.updateTrack(refreshed)
        await persist()

        if let currentEntryID = value.currentEntryID,
           snapshot.entries.first(where: { $0.id == currentEntryID })?.trackID == trackID {
            let wasPlaying = value.state == .playing
            let position = value.position
            try await prepareCurrent(
                entryID: currentEntryID,
                shouldPlay: wasPlaying,
                initialPosition: position
            )
        } else {
            await restageNext()
            publish()
            await persist()
        }
    }

    private func open(_ urls: [URL]) async {
        let result = await importer.importURLs(urls)
        guard !result.tracks.isEmpty else {
            if let failure = result.failures.first { fail(.init(code: .inaccessible, message: failure.reason)) }
            return
        }
        reportImportFailures(result.failures)
        await releaseAllTracks(stoppingEngine: true)
        await queue.replace(with: result.tracks)
        value.currentEntryID = nil
        value.position = 0
        value.duration = nil
        await traverse(.forward, cause: .manual, shouldPlay: true)
    }

    private func append(_ urls: [URL]) async {
        let result = await importer.importURLs(urls)
        guard !result.tracks.isEmpty else { reportImportFailures(result.failures); return }
        reportImportFailures(result.failures)
        await queue.append(result.tracks)
        if current != nil || value.currentEntryID != nil { await restageNext() }
        publish(); await persist()
    }

    private func play() async {
        let queueValue = await queue.snapshot()
        if let selected = queueValue.selectedEntryID, selected != value.currentEntryID {
            await load(entryID: selected, shouldPlay: true, traversalCause: .manual)
            return
        }
        if current == nil, let entryID = value.currentEntryID {
            await load(entryID: entryID, shouldPlay: true, traversalCause: .manual, initialPosition: value.position)
            return
        }
        if current == nil {
            await traverse(.forward, cause: .manual, shouldPlay: true)
            return
        }
        do {
            try await engine.play(generation: current!.generation)
            value.state = .playing
            publish(); await persist()
        } catch { fail(playbackFailure(error)) }
    }

    private func pause() async {
        guard let current else { return }
        await engine.pause(generation: current.generation)
        value.state = .paused
        publish(); await persist()
    }

    private func stop() async {
        guard let current else {
            value.state = value.currentEntryID == nil ? .idle : .stopped
            value.position = 0
            publish(); await persist()
            return
        }
        await engine.stop(generation: current.generation)
        value.state = .stopped
        value.position = 0
        publish(); await persist()
    }

    private func seek(to requested: TimeInterval) async {
        guard requested.isFinite, requested >= 0, current != nil else { return }
        let wasPlaying = value.state == .playing
        let generation = nextGeneration()
        do {
            try await engine.seek(to: requested, generation: generation)
            current = current.map { PreparedTrack(entryID: $0.entryID, generation: generation, lease: $0.lease) }
            value.position = value.duration.map { min(requested, $0) } ?? requested
            value.state = wasPlaying ? .playing : .paused
            if let entryID = value.currentEntryID { await queue.commitPlaying(entryID, generation: generation) }
            await restageNext()
            publish(); await persist()
        } catch { fail(playbackFailure(error)) }
    }

    private func mutateQueue(_ command: PlayerCommand) async {
        do {
            try await queue.apply(command)
            let snapshot = await queue.snapshot()
            if snapshot.entries.isEmpty {
                await releaseAllTracks(stoppingEngine: true)
                await queue.commitPlaying(nil, generation: nextGeneration())
                value.currentEntryID = nil
                value.position = 0
                value.duration = nil
                value.state = .idle
                publish(); await persist()
                return
            }
            await restageNext()
            publish(); await persist()
        } catch { fail(playbackFailure(error)) }
    }

    private func traverse(_ direction: TraversalDirection, cause: TraversalCause, shouldPlay: Bool) async {
        if cause == .manual { automaticFailureAttempts.removeAll() }
        let candidate = await queue.proposedEntry(after: value.currentEntryID, direction: direction, cause: cause)
        guard let candidate else {
            if cause == .automaticEnd {
                value.state = .stopped
                value.position = 0
                publish(); await persist()
            }
            return
        }
        await load(entryID: candidate, shouldPlay: shouldPlay, traversalCause: cause)
    }

    /// Attempts each occurrence once at most, so Repeat All and shuffle cannot loop on bad files.
    private func load(entryID first: QueueEntryID, shouldPlay: Bool, traversalCause: TraversalCause, initialPosition: TimeInterval = 0) async {
        let queueValue = await queue.snapshot()
        var candidate: QueueEntryID? = first
        var attempted = Set<QueueEntryID>()
        var lastFailure: PlaybackFailure?
        while let entryID = candidate, attempted.count < queueValue.entries.count, !attempted.contains(entryID) {
            attempted.insert(entryID)
            do {
                try await prepareCurrent(entryID: entryID, shouldPlay: shouldPlay, initialPosition: initialPosition)
                return
            } catch {
                lastFailure = playbackFailure(error)
                if traversalCause == .automaticEnd { automaticFailureAttempts.insert(entryID) }
            }
            let proposed = await queue.proposedEntry(after: entryID, direction: .forward, cause: traversalCause)
            if let proposed, !attempted.contains(proposed) { candidate = proposed }
            else { candidate = queueValue.entries.first(where: { !attempted.contains($0.id) })?.id }
        }
        fail(lastFailure ?? PlaybackFailure(code: .unsupported, message: "No playable item was found in the queue"))
        await persist()
    }

    private func prepareCurrent(entryID: QueueEntryID, shouldPlay: Bool, initialPosition: TimeInterval) async throws {
        let queueValue = await queue.snapshot()
        guard let entry = queueValue.entries.first(where: { $0.id == entryID }), let track = queueValue.tracks[entry.trackID] else {
            throw PlaybackFailure(code: .inaccessible, message: "The selected queue item is no longer available")
        }
        let lease = try await resolve(track)
        let decoder: any Decoder
        do { decoder = try await decoderFactory(lease.url) }
        catch { await lease.release(); throw error }
        let generation = nextGeneration()
        await releaseAllTracks(stoppingEngine: true)
        current = PreparedTrack(entryID: entryID, generation: generation, lease: lease)
        value.state = .loading
        value.currentEntryID = entryID
        value.position = 0
        let format = await decoder.format
        value.duration = format.frameCount.map { Double($0) / format.sampleRate }
        publish()
        do {
            try await engine.prepare(current: AudioTrackPreparation(entryID: entryID, generation: generation, decoder: decoder), next: nil)
            await queue.commitPlaying(entryID, generation: generation)
            if initialPosition > 0 {
                try await engine.seek(to: initialPosition, generation: generation)
                value.position = value.duration.map { min(initialPosition, $0) } ?? initialPosition
            }
            await stageNext(after: entryID)
            if shouldPlay {
                try await engine.play(generation: generation)
                value.state = .playing
            } else { value.state = .paused }
            publish(); await persist()
        } catch {
            if current?.generation == generation { await current?.lease.release(); current = nil }
            throw error
        }
    }

    private func stageNext(after entryID: QueueEntryID) async {
        let snapshot = await queue.snapshot()
        var candidate = await queue.proposedEntry(after: entryID, direction: .forward, cause: .automaticEnd)
        var attempted = Set<QueueEntryID>()
        while let nextID = candidate {
            guard attempted.insert(nextID).inserted, attempted.count <= snapshot.entries.count else { break }
            do {
                let prepared = try await makePreparation(entryID: nextID)
                do {
                    try await engine.updateNext(prepared.preparation)
                    stagedNext = prepared.track
                    return
                } catch { await prepared.track.lease.release(); throw error }
            } catch {
                let proposed = await queue.proposedEntry(after: nextID, direction: .forward, cause: .automaticEnd)
                if let proposed, !attempted.contains(proposed) { candidate = proposed }
                else { candidate = snapshot.entries.first(where: { !attempted.contains($0.id) && $0.id != entryID })?.id }
            }
        }
        try? await engine.updateNext(nil)
        await stagedNext?.lease.release()
        stagedNext = nil
    }

    private func restageNext() async {
        guard let current else { return }
        try? await engine.updateNext(nil)
        await stagedNext?.lease.release()
        stagedNext = nil
        await stageNext(after: current.entryID)
    }

    private func makePreparation(entryID: QueueEntryID) async throws -> (preparation: AudioTrackPreparation, track: PreparedTrack) {
        let snapshot = await queue.snapshot()
        guard let entry = snapshot.entries.first(where: { $0.id == entryID }), let track = snapshot.tracks[entry.trackID] else {
            throw PlaybackFailure(code: .inaccessible, message: "The next queue item is unavailable")
        }
        let lease = try await resolve(track)
        do {
            let decoder = try await decoderFactory(lease.url)
            let generation = nextGeneration()
            return (AudioTrackPreparation(entryID: entryID, generation: generation, decoder: decoder), PreparedTrack(entryID: entryID, generation: generation, lease: lease))
        } catch { await lease.release(); throw error }
    }

    private func resolve(_ track: TrackReference) async throws -> any FileAccessLease {
        switch try await access.resolve(track) {
        case .granted(let lease): return lease
        case .needsReauthorization: throw PlaybackFailure(code: .inaccessible, message: "File access must be authorized again")
        }
    }

    private func receive(_ event: AudioEngineEvent) async {
        switch event {
        case .prepared(let entryID, let generation):
            guard current?.entryID == entryID, current?.generation == generation else { return }
        case .transitioned(let entryID, let generation):
            guard stagedNext?.entryID == entryID, stagedNext?.generation == generation else { return }
            await current?.lease.release()
            current = stagedNext
            stagedNext = nil
            value.currentEntryID = entryID
            value.position = 0
            value.state = .playing
            automaticFailureAttempts.removeAll()
            generationCounter = max(generationCounter, generation.rawValue)
            await queue.commitPlaying(entryID, generation: generation)
            let snapshot = await queue.snapshot()
            if let entry = snapshot.entries.first(where: { $0.id == entryID }), let track = snapshot.tracks[entry.trackID], case .loaded(let metadata) = track.metadata {
                value.duration = metadata.duration
            } else { value.duration = nil }
            await stageNext(after: entryID)
            publish(); await persist()
        case .position(let position, let generation):
            guard current?.generation == generation, position.isFinite, position >= 0 else { return }
            value.position = position
            publish()
            if abs(position - lastPersistedPosition) >= 5 { await persist() }
        case .ended(let entryID, let generation):
            guard current?.entryID == entryID, current?.generation == generation else { return }
            automaticFailureAttempts.removeAll()
            await traverse(.forward, cause: .automaticEnd, shouldPlay: true)
        case .failed(let failure, let generation):
            guard current?.generation == generation || stagedNext?.generation == generation else { return }
            if stagedNext?.generation == generation {
                await stagedNext?.lease.release(); stagedNext = nil
                if let current { await stageNext(after: current.entryID) }
            } else {
                guard let failedID = current?.entryID else { return }
                automaticFailureAttempts.insert(failedID)
                let snapshot = await queue.snapshot()
                if automaticFailureAttempts.count >= snapshot.entries.count {
                    fail(failure); await persist(); return
                }
                let proposed = await queue.proposedEntry(after: failedID, direction: .forward, cause: .automaticEnd)
                let candidate = proposed.flatMap { automaticFailureAttempts.contains($0) ? nil : $0 }
                    ?? snapshot.entries.first(where: { !automaticFailureAttempts.contains($0.id) })?.id
                if let candidate { await load(entryID: candidate, shouldPlay: true, traversalCause: .automaticEnd) }
                else { fail(failure); await persist() }
            }
        case .outputUnavailable(let generation):
            guard current?.generation == generation else { return }
            fail(PlaybackFailure(code: .outputUnavailable, message: "Audio output is unavailable")); await persist()
        }
    }

    private func releaseAllTracks(stoppingEngine: Bool) async {
        if stoppingEngine, let current { await engine.stop(generation: current.generation) }
        try? await engine.updateNext(nil)
        await current?.lease.release()
        await stagedNext?.lease.release()
        current = nil
        stagedNext = nil
    }

    private func persist() async {
        let queueValue = await queue.snapshot()
        let durableCurrent = value.currentEntryID.flatMap { id in queueValue.entries.contains(where: { $0.id == id }) ? id : nil }
        let referenced = Set(queueValue.entries.map(\.trackID))
        var state = sessionTemplate
        state.queue = queueValue.entries
        state.tracks = queueValue.tracks.values.filter { referenced.contains($0.id) }.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        state.currentEntryID = durableCurrent
        state.selectedEntryID = queueValue.selectedEntryID
        state.isShuffled = queueValue.isShuffled
        state.repeatMode = queueValue.repeatMode
        state.position = durableCurrent == nil ? 0 : value.position
        state.volume = value.volume
        state.equalizer = value.equalizer
        do {
            try await sessions.save(state)
            sessionTemplate = state
            lastPersistedPosition = state.position
        } catch {
            reportNotice("MacAmp couldn’t save the current session: \(error.localizedDescription)")
        }
    }

    private func reportImportFailures(_ failures: [FileImportFailure]) {
        guard !failures.isEmpty else { return }
        let examples = failures.prefix(3).map { $0.url.lastPathComponent.isEmpty ? $0.url.absoluteString : $0.url.lastPathComponent }
        let suffix = failures.count > examples.count ? " and \(failures.count - examples.count) more" : ""
        reportNotice("Skipped \(failures.count) playlist item\(failures.count == 1 ? "" : "s"): \(examples.joined(separator: ", "))\(suffix).")
    }

    private func reportNotice(_ message: String) {
        guard message != lastNotice else { return }
        lastNotice = message
        noticeContinuation.yield(message)
    }

    private func nextGeneration() -> PlaybackGeneration {
        generationCounter &+= 1
        return PlaybackGeneration(rawValue: generationCounter)
    }

    private func publish() { value.revision &+= 1; continuation.yield(value) }
    private func fail(_ failure: PlaybackFailure) { value.state = .failed(failure); publish() }
    private func playbackFailure(_ error: Error) -> PlaybackFailure {
        if let failure = error as? PlaybackFailure { return failure }
        if let native = error as? NativeAudioError {
            let code: PlaybackFailure.Code
            switch native {
            case .unsupportedChannelCount, .unsupportedChainedStream: code = .unsupported
            case .corruptFile: code = .corrupt
            default: code = .unknown
            }
            return PlaybackFailure(code: code, message: native.localizedDescription)
        }
        return PlaybackFailure(code: .unknown, message: error.localizedDescription)
    }
}
