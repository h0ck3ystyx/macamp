import Foundation
import Contracts

public struct PlayerUITrackRow: Equatable, Sendable, Identifiable {
    public let id: QueueEntryID
    public let title: String
    public let detail: String?
    public let duration: TimeInterval?
    public let isSelected: Bool
    public let isPlaying: Bool
    public let isUnavailable: Bool
}

public struct PlayerUIStateModel: Equatable, Sendable {
    public var playback: PlaybackSnapshot
    public var queue: QueueSnapshot
    public var filterText: String

    public init(playback: PlaybackSnapshot = PlaybackSnapshot(), queue: QueueSnapshot = QueueSnapshot(), filterText: String = "") {
        self.playback = playback; self.queue = queue; self.filterText = filterText
    }

    public var rows: [PlayerUITrackRow] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allRows }
        return allRows.filter { row in
            guard let entry = queue.entries.first(where: { $0.id == row.id }), let track = queue.tracks[entry.trackID] else { return false }
            let metadata: TrackMetadata?
            if case .loaded(let loaded) = track.metadata { metadata = loaded } else { metadata = nil }
            return [row.title, row.detail, metadata?.album, track.lastKnownURL.deletingPathExtension().lastPathComponent]
                .compactMap { $0 }
                .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private var allRows: [PlayerUITrackRow] {
        queue.entries.map { entry in
            let track = queue.tracks[entry.trackID]
            let metadata: TrackMetadata?
            let unavailable: Bool
            switch track?.metadata {
            case .loaded(let value): metadata = value; unavailable = false
            case .unavailable: metadata = nil; unavailable = true
            default: metadata = nil; unavailable = false
            }
            return PlayerUITrackRow(
                id: entry.id,
                title: metadata?.title ?? track?.lastKnownURL.deletingPathExtension().lastPathComponent ?? "Loading…",
                detail: metadata?.artist,
                duration: metadata?.duration,
                isSelected: queue.selectedEntryID == entry.id,
                isPlaying: (queue.playingEntryID ?? playback.currentEntryID) == entry.id,
                isUnavailable: unavailable
            )
        }
    }

    public var currentRow: PlayerUITrackRow? { allRows.first(where: \.isPlaying) }
    public var title: String { currentRow?.title ?? (queue.entries.isEmpty ? "Drop audio here" : "Nothing playing") }
    public var artist: String {
        if let currentRow { return currentRow.detail ?? "Local file" }
        return queue.entries.isEmpty ? "Open files to begin" : "Select a track"
    }
    public var technicalText: String? {
        guard let entry = queue.entries.first(where: { $0.id == (queue.playingEntryID ?? playback.currentEntryID) }),
              case .loaded(let metadata) = queue.tracks[entry.trackID]?.metadata else { return nil }
        let value = [metadata.codec, metadata.sampleRate.map { String(format: "%.1f kHz", $0 / 1_000) }, metadata.channelCount.map { $0 == 1 ? "Mono" : ($0 == 2 ? "Stereo" : "\($0) ch") }].compactMap { $0 }.joined(separator: " · ")
        return value.isEmpty ? nil : value
    }
    public var statusText: String {
        switch playback.state {
        case .idle: queue.entries.isEmpty ? "EMPTY PLAYLIST" : "READY"
        case .loading: "LOADING…"
        case .playing: "PLAYING"
        case .paused: "PAUSED"
        case .stopped: "STOPPED"
        case .failed(let failure): "ERROR · \(failure.message)"
        }
    }
    public var playPauseCommand: PlayerCommand {
        if case .playing = playback.state { return .pause }
        return .play
    }
    public var nextRepeatMode: RepeatMode {
        switch queue.repeatMode { case .off: .all; case .all: .one; case .one: .off }
    }
    public func seekCommand(fraction: Double) -> PlayerCommand? {
        guard let duration = playback.duration, duration > 0 else { return nil }
        return .seek(to: duration * min(max(fraction, 0), 1))
    }
    public func volumeCommand(_ value: Double) -> PlayerCommand { .setVolume(min(max(value, 0), 1)) }
    public func equalizerCommand(band: Int, gain: Double) -> PlayerCommand? {
        guard playback.equalizer.bandGains.indices.contains(band) else { return nil }
        var settings = playback.equalizer; settings.bandGains[band] = min(max(gain, -12), 12)
        return .setEqualizer(settings)
    }
    public func preampCommand(_ gain: Double) -> PlayerCommand {
        var settings = playback.equalizer; settings.preampGain = min(max(gain, -12), 12); return .setEqualizer(settings)
    }
    public var toggleBypassCommand: PlayerCommand {
        var settings = playback.equalizer; settings.isBypassed.toggle(); return .setEqualizer(settings)
    }
    public var resetEqualizerCommand: PlayerCommand { .setEqualizer(EQSettings(isBypassed: false)) }
}

public enum PlayerUIPreviewAdapter {
    public static func snapshots(from preview: PlayerUIPreviewState) -> (PlaybackSnapshot, QueueSnapshot) {
        var tracks: [TrackID: TrackReference] = [:]; var entries: [QueueEntry] = []
        for (index, name) in preview.playlist.enumerated() {
            let trackID = TrackID(); let entry = QueueEntry(trackID: trackID)
            let parts = name.components(separatedBy: " — ")
            tracks[trackID] = TrackReference(lastKnownURL: URL(fileURLWithPath: "/Preview/\(name).flac"), metadata: .loaded(TrackMetadata(title: parts.last, artist: parts.count > 1 ? parts.first : nil, duration: index == 0 ? preview.duration : nil, codec: "FLAC", sampleRate: 44_100, channelCount: 2)))
            entries.append(entry)
        }
        let current = entries.first?.id
        return (
            PlaybackSnapshot(state: .playing, currentEntryID: current, position: preview.elapsed, duration: preview.duration, volume: 0.78, equalizer: EQSettings(isBypassed: false)),
            QueueSnapshot(entries: entries, tracks: tracks, selectedEntryID: current, playingEntryID: current)
        )
    }
}
