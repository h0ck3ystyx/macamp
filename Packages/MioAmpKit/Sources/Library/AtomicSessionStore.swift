import Contracts
import Foundation

public enum SessionStoreError: Error, Equatable, Sendable {
    case unsupportedSchema(found: Int, supported: Int)
    case corruptPrimaryAndBackup(primary: String, backup: String?)
    case invalidState(String)
}

public actor AtomicSessionStore: SessionStore {
    public nonisolated let fileURL: URL
    public nonisolated var backupURL: URL { fileURL.appendingPathExtension("backup") }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> SessionState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try decode(Data(contentsOf: fileURL))
        } catch let error as SessionStoreError {
            if case .unsupportedSchema = error { throw error }
            return try loadBackup(after: error.localizedDescription)
        } catch {
            return try loadBackup(after: error.localizedDescription)
        }
    }

    public func save(_ state: SessionState) throws {
        guard state.schemaVersion == SessionState.currentSchemaVersion else {
            throw SessionStoreError.unsupportedSchema(found: state.schemaVersion, supported: SessionState.currentSchemaVersion)
        }
        try validate(state)
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: fileURL.path) {
            if manager.fileExists(atPath: backupURL.path) { try manager.removeItem(at: backupURL) }
            try manager.copyItem(at: fileURL, to: backupURL)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic])
    }

    private func decode(_ data: Data) throws -> SessionState {
        var decoded = try JSONDecoder().decode(SessionState.self, from: data)
        switch decoded.schemaVersion {
        case SessionState.currentSchemaVersion:
            break
        case 1, 2:
            // Contracts supplies backward-compatible defaults for fields introduced in v2/v3.
            // The next ordinary save durably rewrites the migrated representation while load
            // leaves the source file untouched for recovery if startup is interrupted.
            decoded.schemaVersion = SessionState.currentSchemaVersion
        default:
            throw SessionStoreError.unsupportedSchema(found: decoded.schemaVersion, supported: SessionState.currentSchemaVersion)
        }
        try validate(decoded)
        return decoded
    }

    private func loadBackup(after primaryError: String) throws -> SessionState {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw SessionStoreError.corruptPrimaryAndBackup(primary: primaryError, backup: nil)
        }
        do {
            return try decode(Data(contentsOf: backupURL))
        } catch {
            throw SessionStoreError.corruptPrimaryAndBackup(
                primary: primaryError,
                backup: error.localizedDescription
            )
        }
    }

    private func validate(_ state: SessionState) throws {
        let trackIDs = Set(state.tracks.map(\.id))
        guard state.queue.allSatisfy({ trackIDs.contains($0.trackID) }) else {
            throw SessionStoreError.invalidState("Queue refers to a missing track")
        }
        if let current = state.currentEntryID, !state.queue.contains(where: { $0.id == current }) {
            throw SessionStoreError.invalidState("Current entry is absent from the queue")
        }
        if let selected = state.selectedEntryID, !state.queue.contains(where: { $0.id == selected }) {
            throw SessionStoreError.invalidState("Selected entry is absent from the queue")
        }
        guard state.position.isFinite, state.position >= 0 else {
            throw SessionStoreError.invalidState("Position must be finite and nonnegative")
        }
        guard state.volume.isFinite, (0...1).contains(state.volume) else {
            throw SessionStoreError.invalidState("Volume must be finite and between zero and one")
        }
        guard state.equalizer.preampGain.isFinite,
              state.equalizer.bandGains.allSatisfy(\.isFinite) else {
            throw SessionStoreError.invalidState("Equalizer gains must be finite")
        }
        guard !state.skinID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SessionStoreError.invalidState("Skin identifier must not be empty")
        }
        guard state.windowLayout.scale.isFinite, state.windowLayout.scale > 0 else {
            throw SessionStoreError.invalidState("Window scale must be finite and positive")
        }
        guard state.visualization.dwellSeconds.isFinite, (10...120).contains(state.visualization.dwellSeconds),
              state.visualization.transitionSeconds.isFinite, (0...5).contains(state.visualization.transitionSeconds),
              state.visualization.sensitivity.isFinite, (0.25...4).contains(state.visualization.sensitivity),
              !state.visualization.presetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SessionStoreError.invalidState("Visualization settings are outside supported bounds")
        }
    }
}

public enum SessionRestoration {
    /// Relaunch is deliberately inert: a prior current item is presented as paused and never
    /// resumes through a newly selected output device without the user's action.
    public static func playbackSnapshot(from state: SessionState) -> PlaybackSnapshot {
        PlaybackSnapshot(
            state: state.currentEntryID == nil ? .idle : .paused,
            currentEntryID: state.currentEntryID,
            position: state.position,
            volume: state.volume,
            equalizer: state.equalizer
        )
    }

    public static func queueSnapshot(from state: SessionState) -> QueueSnapshot {
        QueueSnapshot(
            entries: state.queue,
            tracks: Dictionary(state.tracks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }),
            selectedEntryID: state.selectedEntryID,
            playingEntryID: state.currentEntryID,
            isShuffled: state.isShuffled,
            repeatMode: state.repeatMode
        )
    }
}
