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
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)
        guard decoded.schemaVersion == SessionState.currentSchemaVersion else {
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
        guard state.position.isFinite, state.position >= 0 else {
            throw SessionStoreError.invalidState("Position must be finite and nonnegative")
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
}
