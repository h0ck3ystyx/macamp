import Foundation

public struct QueueSnapshot: Equatable, Sendable {
    public var revision: UInt64
    public var entries: [QueueEntry]
    public var tracks: [TrackID: TrackReference]
    public var selectedEntryID: QueueEntryID?
    public var playingEntryID: QueueEntryID?
    public var isShuffled: Bool
    public var repeatMode: RepeatMode

    public init(
        revision: UInt64 = 0,
        entries: [QueueEntry] = [],
        tracks: [TrackID: TrackReference] = [:],
        selectedEntryID: QueueEntryID? = nil,
        playingEntryID: QueueEntryID? = nil,
        isShuffled: Bool = false,
        repeatMode: RepeatMode = .off
    ) {
        self.revision = revision
        self.entries = entries
        self.tracks = tracks
        self.selectedEntryID = selectedEntryID
        self.playingEntryID = playingEntryID
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
    }
}

public enum TraversalDirection: Sendable { case forward, backward }
public enum TraversalCause: Equatable, Sendable { case manual, automaticEnd }

public protocol QueueStore: Sendable {
    func snapshot() async -> QueueSnapshot
    func replace(with tracks: [TrackReference]) async
    func append(_ tracks: [TrackReference]) async
    /// Replaces the durable reference for an existing track while preserving every
    /// queue entry that points at its stable TrackID.
    func updateTrack(_ track: TrackReference) async throws
    func apply(_ command: PlayerCommand) async throws
    @discardableResult func undoLastMutation() async -> Bool
    func proposedEntry(after current: QueueEntryID?, direction: TraversalDirection, cause: TraversalCause) async -> QueueEntryID?
    func commitPlaying(_ entryID: QueueEntryID?, generation: PlaybackGeneration) async
}

public protocol PlaybackCoordinator: Sendable {
    var snapshots: AsyncStream<PlaybackSnapshot> { get }
    func send(_ command: PlayerCommand) async
}

public struct AudioFormatDescription: Codable, Equatable, Sendable {
    public var codec: String
    public var sampleRate: Double
    public var channelCount: Int
    public var frameCount: Int64?
    public var encoderDelayFrames: Int64?
    public var trailingPaddingFrames: Int64?

    public init(
        codec: String,
        sampleRate: Double,
        channelCount: Int,
        frameCount: Int64? = nil,
        encoderDelayFrames: Int64? = nil,
        trailingPaddingFrames: Int64? = nil
    ) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
        self.encoderDelayFrames = encoderDelayFrames
        self.trailingPaddingFrames = trailingPaddingFrames
    }
}

public struct PCMChunk: Sendable {
    public var interleavedSamples: [Float]
    public var frameCount: Int
    public var isEndOfStream: Bool

    public init(interleavedSamples: [Float], frameCount: Int, isEndOfStream: Bool) {
        self.interleavedSamples = interleavedSamples
        self.frameCount = frameCount
        self.isEndOfStream = isEndOfStream
    }
}

public protocol Decoder: Sendable {
    var format: AudioFormatDescription { get async }
    func seek(toFrame frame: Int64) async throws
    func read(maxFrames: Int) async throws -> PCMChunk
}

public struct AudioTrackPreparation: Sendable {
    public let entryID: QueueEntryID
    public let generation: PlaybackGeneration
    public let decoder: any Decoder

    public init(entryID: QueueEntryID, generation: PlaybackGeneration, decoder: any Decoder) {
        self.entryID = entryID
        self.generation = generation
        self.decoder = decoder
    }
}

public enum AudioEngineEvent: Sendable, Equatable {
    case prepared(entryID: QueueEntryID, generation: PlaybackGeneration)
    case transitioned(entryID: QueueEntryID, generation: PlaybackGeneration)
    case position(TimeInterval, generation: PlaybackGeneration)
    case ended(entryID: QueueEntryID, generation: PlaybackGeneration)
    case failed(PlaybackFailure, generation: PlaybackGeneration)
    case outputUnavailable(generation: PlaybackGeneration)
}

public protocol AudioEngineClient: Sendable {
    var events: AsyncStream<AudioEngineEvent> { get }
    func prepare(current: AudioTrackPreparation, next: AudioTrackPreparation?) async throws
    func updateNext(_ next: AudioTrackPreparation?) async throws
    func play(generation: PlaybackGeneration) async throws
    func pause(generation: PlaybackGeneration) async
    func stop(generation: PlaybackGeneration) async
    func seek(to time: TimeInterval, generation: PlaybackGeneration) async throws
    func setVolume(_ volume: Double) async
    func setEqualizer(_ settings: EQSettings) async
}

public protocol FileAccessLease: Sendable {
    var url: URL { get }
    func release() async
}

public enum FileAccessResolution: Sendable {
    case granted(any FileAccessLease)
    case needsReauthorization(lastKnownURL: URL)
}

public protocol FileAccessService: Sendable {
    func bookmark(for url: URL) async throws -> Data
    func resolve(_ track: TrackReference) async throws -> FileAccessResolution
    func reauthorize(_ track: TrackReference, at url: URL) async throws -> TrackReference
}

public extension FileAccessService {
    func reauthorize(_ track: TrackReference, at url: URL) async throws -> TrackReference {
        TrackReference(
            id: track.id,
            lastKnownURL: url,
            securityScopedBookmark: try await bookmark(for: url),
            metadata: track.metadata
        )
    }
}
