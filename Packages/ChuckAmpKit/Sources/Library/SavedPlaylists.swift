import Contracts
import Foundation

public struct SavedPlaylistID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }
}

public struct SavedPlaylist: Codable, Equatable, Identifiable, Sendable {
    public let id: SavedPlaylistID
    public var name: String
    public var tracks: [TrackReference]
    public var modifiedAt: Date

    public init(
        id: SavedPlaylistID = SavedPlaylistID(),
        name: String,
        tracks: [TrackReference],
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.modifiedAt = modifiedAt
    }
}

public enum SavedPlaylistStoreError: Error, Equatable, Sendable {
    case invalidName
    case queueRefersToMissingTrack(TrackID)
    case unknownPlaylist(SavedPlaylistID)
    case unsupportedSchema(Int)
}

/// Durable named playlists are value snapshots and never alias the active queue.
public actor SavedPlaylistStore {
    private struct Catalog: Codable, Equatable, Sendable {
        static let currentSchemaVersion = 1
        var schemaVersion: Int = currentSchemaVersion
        var playlists: [SavedPlaylist] = []
    }

    public nonisolated let fileURL: URL
    private var catalog: Catalog?
    private var undoStack: [Catalog] = []
    private let undoLimit: Int

    public init(fileURL: URL, undoLimit: Int = 50) {
        self.fileURL = fileURL
        self.undoLimit = max(0, undoLimit)
    }

    public func all() throws -> [SavedPlaylist] {
        try ensureLoaded()
        return catalog!.playlists.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    public func save(name: String, queue: QueueSnapshot) throws -> SavedPlaylist {
        let tracks = try queue.entries.map { entry in
            guard let track = queue.tracks[entry.trackID] else {
                throw SavedPlaylistStoreError.queueRefersToMissingTrack(entry.trackID)
            }
            return track
        }
        return try save(name: name, tracks: tracks)
    }

    @discardableResult
    public func save(
        id: SavedPlaylistID = SavedPlaylistID(),
        name: String,
        tracks: [TrackReference]
    ) throws -> SavedPlaylist {
        try ensureLoaded()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SavedPlaylistStoreError.invalidName }
        let prior = catalog!
        recordUndo()
        let playlist = SavedPlaylist(id: id, name: trimmed, tracks: tracks)
        if let index = catalog!.playlists.firstIndex(where: { $0.id == id }) {
            catalog!.playlists[index] = playlist
        } else {
            catalog!.playlists.append(playlist)
        }
        do { try persist() }
        catch {
            catalog = prior
            if undoLimit > 0 { _ = undoStack.popLast() }
            throw error
        }
        return playlist
    }

    public func rename(_ id: SavedPlaylistID, to name: String) throws {
        try ensureLoaded()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SavedPlaylistStoreError.invalidName }
        guard let index = catalog!.playlists.firstIndex(where: { $0.id == id }) else {
            throw SavedPlaylistStoreError.unknownPlaylist(id)
        }
        let prior = catalog!
        recordUndo()
        catalog!.playlists[index].name = trimmed
        catalog!.playlists[index].modifiedAt = Date()
        do { try persist() }
        catch {
            catalog = prior
            if undoLimit > 0 { _ = undoStack.popLast() }
            throw error
        }
    }

    public func remove(_ id: SavedPlaylistID) throws {
        try ensureLoaded()
        guard catalog!.playlists.contains(where: { $0.id == id }) else {
            throw SavedPlaylistStoreError.unknownPlaylist(id)
        }
        let prior = catalog!
        recordUndo()
        catalog!.playlists.removeAll { $0.id == id }
        do { try persist() }
        catch {
            catalog = prior
            if undoLimit > 0 { _ = undoStack.popLast() }
            throw error
        }
    }

    public func canUndo() throws -> Bool {
        try ensureLoaded()
        return !undoStack.isEmpty
    }

    @discardableResult
    public func undo() throws -> Bool {
        try ensureLoaded()
        guard let prior = undoStack.popLast() else { return false }
        let current = catalog!
        catalog = prior
        do { try persist() }
        catch {
            catalog = current
            undoStack.append(prior)
            throw error
        }
        return true
    }

    private func ensureLoaded() throws {
        guard catalog == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            catalog = Catalog()
            return
        }
        let decoded = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: fileURL))
        guard decoded.schemaVersion == Catalog.currentSchemaVersion else {
            throw SavedPlaylistStoreError.unsupportedSchema(decoded.schemaVersion)
        }
        catalog = decoded
    }

    private func recordUndo() {
        guard undoLimit > 0, let catalog else { return }
        undoStack.append(catalog)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
    }

    private func persist() throws {
        guard let catalog else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(catalog).write(to: fileURL, options: [.atomic])
    }
}
