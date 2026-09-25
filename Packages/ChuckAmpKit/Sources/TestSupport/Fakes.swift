import Contracts
import Foundation

public actor FakeSessionStore: SessionStore {
    public private(set) var savedState: SessionState?

    public init(savedState: SessionState? = nil) {
        self.savedState = savedState
    }

    public func load() async throws -> SessionState? { savedState }
    public func save(_ state: SessionState) async throws { savedState = state }
}

public actor FakeQueueStore: QueueStore {
    private var value = QueueSnapshot()

    public init() {}

    public func snapshot() async -> QueueSnapshot { value }

    public func replace(with tracks: [TrackReference]) async {
        value.revision += 1
        value.tracks = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        value.entries = tracks.map { QueueEntry(trackID: $0.id) }
        value.selectedEntryID = value.entries.first?.id
    }

    public func append(_ tracks: [TrackReference]) async {
        value.revision += 1
        for track in tracks {
            value.tracks[track.id] = track
            value.entries.append(QueueEntry(trackID: track.id))
        }
    }

    public func apply(_ command: PlayerCommand) async throws {
        value.revision += 1
        switch command {
        case .select(let entryID): value.selectedEntryID = entryID
        case .remove(let entryIDs): value.entries.removeAll { entryIDs.contains($0.id) }
        case .setShuffle(let enabled): value.isShuffled = enabled
        case .setRepeat(let mode): value.repeatMode = mode
        default: break
        }
    }

    public func proposedEntry(after current: QueueEntryID?, direction: TraversalDirection, cause: TraversalCause) async -> QueueEntryID? {
        guard !value.entries.isEmpty else { return nil }
        if cause == .automaticEnd, value.repeatMode == .one { return current }
        guard let current, let index = value.entries.firstIndex(where: { $0.id == current }) else {
            return direction == .forward ? value.entries.first?.id : value.entries.last?.id
        }
        switch direction {
        case .forward:
            return value.entries.indices.contains(index + 1) ? value.entries[index + 1].id : nil
        case .backward:
            return value.entries.indices.contains(index - 1) ? value.entries[index - 1].id : nil
        }
    }

    public func commitPlaying(_ entryID: QueueEntryID?, generation: PlaybackGeneration) async {
        _ = generation
        value.revision += 1
        value.playingEntryID = entryID
    }
}
