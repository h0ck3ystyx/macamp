import Foundation

public struct TrackID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }
}

public struct QueueEntryID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }
}

public struct PlaybackGeneration: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public enum MetadataState: Codable, Equatable, Sendable {
    case pending
    case loaded(TrackMetadata)
    case unavailable(reason: String)
}

public struct TrackMetadata: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var duration: TimeInterval?
    public var codec: String?
    public var sampleRate: Double?
    public var channelCount: Int?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        duration: TimeInterval? = nil,
        codec: String? = nil,
        sampleRate: Double? = nil,
        channelCount: Int? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.codec = codec
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

public struct TrackReference: Codable, Equatable, Sendable, Identifiable {
    public let id: TrackID
    public var lastKnownURL: URL
    public var securityScopedBookmark: Data?
    public var metadata: MetadataState

    public init(
        id: TrackID = TrackID(),
        lastKnownURL: URL,
        securityScopedBookmark: Data? = nil,
        metadata: MetadataState = .pending
    ) {
        self.id = id
        self.lastKnownURL = lastKnownURL
        self.securityScopedBookmark = securityScopedBookmark
        self.metadata = metadata
    }
}

public struct QueueEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: QueueEntryID
    public let trackID: TrackID

    public init(id: QueueEntryID = QueueEntryID(), trackID: TrackID) {
        self.id = id
        self.trackID = trackID
    }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one
}

public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case failed(PlaybackFailure)
}

public struct PlaybackFailure: Error, Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case inaccessible
        case unsupported
        case corrupt
        case outputUnavailable
        case cancelled
        case unknown
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public struct EQSettings: Codable, Equatable, Sendable {
    public static let frequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    public var isBypassed: Bool
    public var preampGain: Double
    public var bandGains: [Double]

    public init(isBypassed: Bool = true, preampGain: Double = 0, bandGains: [Double] = Array(repeating: 0, count: 10)) {
        precondition(bandGains.count == Self.frequencies.count, "MacAmp EQ requires ten bands")
        self.isBypassed = isBypassed
        self.preampGain = preampGain
        self.bandGains = bandGains
    }
}

public struct PlaybackSnapshot: Equatable, Sendable {
    public var revision: UInt64
    public var state: PlaybackState
    public var currentEntryID: QueueEntryID?
    public var position: TimeInterval
    public var duration: TimeInterval?
    public var volume: Double
    public var equalizer: EQSettings

    public init(
        revision: UInt64 = 0,
        state: PlaybackState = .idle,
        currentEntryID: QueueEntryID? = nil,
        position: TimeInterval = 0,
        duration: TimeInterval? = nil,
        volume: Double = 1,
        equalizer: EQSettings = EQSettings()
    ) {
        self.revision = revision
        self.state = state
        self.currentEntryID = currentEntryID
        self.position = position
        self.duration = duration
        self.volume = volume
        self.equalizer = equalizer
    }
}

public enum PlayerCommand: Equatable, Sendable {
    case play
    case pause
    case stop
    case seek(to: TimeInterval)
    case previous
    case next
    case open([URL])
    case append([URL])
    case select(QueueEntryID?)
    case remove([QueueEntryID])
    case move(entries: [QueueEntryID], before: QueueEntryID?)
    case setShuffle(Bool)
    case setRepeat(RepeatMode)
    case setVolume(Double)
    case setEqualizer(EQSettings)
}

