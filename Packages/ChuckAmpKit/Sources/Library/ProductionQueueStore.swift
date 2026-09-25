import Contracts
import Foundation

public enum QueueStoreError: Error, Equatable, Sendable {
    case unsupportedCommand
    case unknownEntry(QueueEntryID)
}

/// Actor-isolated queue state with stable entry identities and deterministic traversal.
public actor ProductionQueueStore: QueueStore {
    private struct State: Sendable {
        var snapshot: QueueSnapshot
        var shuffleHistory: [QueueEntryID]
        var shuffleCursor: Int?
        var shuffleDeck: [QueueEntryID]
        var random: SplitMix64
        var lastGeneration: PlaybackGeneration?
    }

    private var state: State
    private var undoStack: [State] = []
    private let undoLimit: Int

    public init(snapshot: QueueSnapshot = QueueSnapshot(), shuffleSeed: UInt64 = 0x4348_5543_4B41_4D50, undoLimit: Int = 50) {
        var random = SplitMix64(seed: shuffleSeed)
        var initialDeck = snapshot.isShuffled
            ? snapshot.entries.map(\.id).filter { $0 != snapshot.playingEntryID }
            : []
        if initialDeck.count > 1 {
            for index in stride(from: initialDeck.count - 1, through: 1, by: -1) {
                let other = Int(random.next() % UInt64(index + 1))
                initialDeck.swapAt(index, other)
            }
        }
        self.state = State(
            snapshot: snapshot,
            shuffleHistory: snapshot.playingEntryID.map { [$0] } ?? [],
            shuffleCursor: snapshot.playingEntryID == nil ? nil : 0,
            shuffleDeck: initialDeck,
            random: random,
            lastGeneration: nil
        )
        self.undoLimit = max(0, undoLimit)
    }

    public func snapshot() -> QueueSnapshot { state.snapshot }

    public func replace(with tracks: [TrackReference]) {
        recordUndo()
        state.snapshot.entries = tracks.map { QueueEntry(trackID: $0.id) }
        state.snapshot.tracks = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        state.snapshot.selectedEntryID = nil
        state.snapshot.playingEntryID = nil
        resetTraversal()
        changed()
    }

    public func append(_ tracks: [TrackReference]) {
        guard !tracks.isEmpty else { return }
        recordUndo()
        for track in tracks {
            state.snapshot.tracks[track.id] = track
            state.snapshot.entries.append(QueueEntry(trackID: track.id))
        }
        if state.snapshot.isShuffled { rebuildShuffleDeck(excluding: state.snapshot.playingEntryID) }
        changed()
    }

    public func apply(_ command: PlayerCommand) throws {
        switch command {
        case .select(let entryID):
            if let entryID, !state.snapshot.entries.contains(where: { $0.id == entryID }) {
                throw QueueStoreError.unknownEntry(entryID)
            }
            guard state.snapshot.selectedEntryID != entryID else { return }
            recordUndo()
            state.snapshot.selectedEntryID = entryID
            changed()

        case .remove(let ids):
            let removed = Set(ids)
            guard state.snapshot.entries.contains(where: { removed.contains($0.id) }) else { return }
            recordUndo()
            let playingTrack = state.snapshot.entries.first(where: { $0.id == state.snapshot.playingEntryID })?.trackID
            state.snapshot.entries.removeAll { removed.contains($0.id) }
            if let selected = state.snapshot.selectedEntryID, removed.contains(selected) {
                state.snapshot.selectedEntryID = nil
            }
            let referenced = Set(state.snapshot.entries.map(\.trackID)).union(playingTrack.map { [$0] } ?? [])
            state.snapshot.tracks = state.snapshot.tracks.filter { referenced.contains($0.key) }
            state.shuffleHistory.removeAll { removed.contains($0) }
            state.shuffleDeck.removeAll { removed.contains($0) }
            normalizeShuffleCursor()
            changed()

        case .move(let ids, let before):
            let moving = Set(ids)
            let ordered = state.snapshot.entries.filter { moving.contains($0.id) }
            guard !ordered.isEmpty else { return }
            recordUndo()
            var remaining = state.snapshot.entries.filter { !moving.contains($0.id) }
            let insertion = before.flatMap { target in remaining.firstIndex(where: { $0.id == target }) } ?? remaining.endIndex
            remaining.insert(contentsOf: ordered, at: insertion)
            state.snapshot.entries = remaining
            changed()

        case .setShuffle(let enabled):
            guard state.snapshot.isShuffled != enabled else { return }
            recordUndo()
            state.snapshot.isShuffled = enabled
            resetTraversal()
            changed()

        case .setRepeat(let mode):
            guard state.snapshot.repeatMode != mode else { return }
            recordUndo()
            state.snapshot.repeatMode = mode
            changed()

        case .open, .append, .play, .pause, .stop, .seek, .previous, .next, .setVolume, .setEqualizer:
            throw QueueStoreError.unsupportedCommand
        }
    }

    public func proposedEntry(
        after current: QueueEntryID?,
        direction: TraversalDirection,
        cause: TraversalCause
    ) -> QueueEntryID? {
        guard !state.snapshot.entries.isEmpty else { return nil }
        if cause == .automaticEnd,
           state.snapshot.repeatMode == .one,
           let current,
           state.snapshot.entries.contains(where: { $0.id == current }) {
            return current
        }
        if state.snapshot.isShuffled {
            return shuffledProposal(after: current, direction: direction)
        }
        return linearProposal(after: current, direction: direction)
    }

    public func commitPlaying(_ entryID: QueueEntryID?, generation: PlaybackGeneration) {
        if let last = state.lastGeneration, generation.rawValue < last.rawValue { return }
        if let entryID,
           !state.snapshot.entries.contains(where: { $0.id == entryID }),
           entryID != state.snapshot.playingEntryID { return }

        state.lastGeneration = generation
        state.snapshot.playingEntryID = entryID
        if state.snapshot.isShuffled, let entryID {
            commitShuffleHistory(entryID)
            state.shuffleDeck.removeAll { $0 == entryID }
        }
        changed()
    }

    public func canUndo() -> Bool { !undoStack.isEmpty }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        let nextRevision = state.snapshot.revision &+ 1
        let latestGeneration = state.lastGeneration
        state = previous
        state.snapshot.revision = nextRevision
        state.lastGeneration = latestGeneration
        return true
    }

    public func updateMetadata(trackID: TrackID, metadata: MetadataState) {
        guard var track = state.snapshot.tracks[trackID] else { return }
        track.metadata = metadata
        state.snapshot.tracks[trackID] = track
        changed()
    }

    private func linearProposal(after current: QueueEntryID?, direction: TraversalDirection) -> QueueEntryID? {
        let entries = state.snapshot.entries
        guard let current, let index = entries.firstIndex(where: { $0.id == current }) else {
            return direction == .forward ? entries.first?.id : entries.last?.id
        }
        switch direction {
        case .forward:
            if index + 1 < entries.count { return entries[index + 1].id }
            return state.snapshot.repeatMode == .all ? entries.first?.id : nil
        case .backward:
            if index > 0 { return entries[index - 1].id }
            return state.snapshot.repeatMode == .all ? entries.last?.id : nil
        }
    }

    private func shuffledProposal(after current: QueueEntryID?, direction: TraversalDirection) -> QueueEntryID? {
        if let current, let historyIndex = state.shuffleHistory.firstIndex(of: current) {
            state.shuffleCursor = historyIndex
        }
        switch direction {
        case .backward:
            guard let cursor = state.shuffleCursor, cursor > 0 else { return nil }
            return state.shuffleHistory[cursor - 1]
        case .forward:
            if let cursor = state.shuffleCursor, cursor + 1 < state.shuffleHistory.count {
                return state.shuffleHistory[cursor + 1]
            }
            if state.shuffleDeck.isEmpty {
                guard state.snapshot.repeatMode == .all else { return nil }
                rebuildShuffleDeck(excluding: current)
            }
            return state.shuffleDeck.last
        }
    }

    private func commitShuffleHistory(_ entryID: QueueEntryID) {
        if let existing = state.shuffleHistory.firstIndex(of: entryID) {
            state.shuffleCursor = existing
            return
        }
        if let cursor = state.shuffleCursor, cursor + 1 < state.shuffleHistory.count {
            state.shuffleHistory.removeSubrange((cursor + 1)..<state.shuffleHistory.count)
        }
        state.shuffleHistory.append(entryID)
        state.shuffleCursor = state.shuffleHistory.count - 1
    }

    private func resetTraversal() {
        state.shuffleHistory = state.snapshot.playingEntryID.map { [$0] } ?? []
        state.shuffleCursor = state.snapshot.playingEntryID == nil ? nil : 0
        rebuildShuffleDeck(excluding: state.snapshot.playingEntryID)
    }

    private func rebuildShuffleDeck(excluding current: QueueEntryID?) {
        state.shuffleDeck = state.snapshot.entries.map(\.id).filter { $0 != current }
        guard state.shuffleDeck.count > 1 else { return }
        for index in stride(from: state.shuffleDeck.count - 1, through: 1, by: -1) {
            let other = Int(state.random.next() % UInt64(index + 1))
            state.shuffleDeck.swapAt(index, other)
        }
    }

    private func normalizeShuffleCursor() {
        guard !state.shuffleHistory.isEmpty else { state.shuffleCursor = nil; return }
        state.shuffleCursor = min(state.shuffleCursor ?? (state.shuffleHistory.count - 1), state.shuffleHistory.count - 1)
    }

    private func recordUndo() {
        guard undoLimit > 0 else { return }
        undoStack.append(state)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
    }

    private func changed() { state.snapshot.revision &+= 1 }
}

private struct SplitMix64: Sendable {
    private var value: UInt64
    init(seed: UInt64) { value = seed }
    mutating func next() -> UInt64 {
        value &+= 0x9E37_79B9_7F4A_7C15
        var result = value
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}
