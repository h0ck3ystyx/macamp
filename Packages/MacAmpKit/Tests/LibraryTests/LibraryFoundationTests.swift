import Contracts
import Foundation
import Library
import Testing

@Test func applicationSupportRenameCopiesLegacyDataWithoutOverwritingNewFiles() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("ChuckAmp", isDirectory: true)
    let preferred = root.appendingPathComponent("MacAmp", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Skins", isDirectory: true), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)
    try Data("legacy session".utf8).write(to: legacy.appendingPathComponent("session.json"))
    try Data("legacy skin".utf8).write(to: legacy.appendingPathComponent("Skins/custom.json"))
    try Data("new playlists".utf8).write(to: preferred.appendingPathComponent("playlists.json"))
    try Data("legacy playlists".utf8).write(to: legacy.appendingPathComponent("playlists.json"))

    let result = try ApplicationSupportMigration.prepare(preferredRoot: preferred, legacyRoot: legacy)

    #expect(result == preferred)
    #expect(try String(contentsOf: preferred.appendingPathComponent("session.json"), encoding: .utf8) == "legacy session")
    #expect(try String(contentsOf: preferred.appendingPathComponent("Skins/custom.json"), encoding: .utf8) == "legacy skin")
    #expect(try String(contentsOf: preferred.appendingPathComponent("playlists.json"), encoding: .utf8) == "new playlists")
}

@Test func duplicateSourcesHaveDistinctEntriesAndMutationsUndo() async throws {
    let track = TrackReference(lastKnownURL: URL(fileURLWithPath: "/tmp/album.mp3"))
    let store = ProductionQueueStore()
    await store.append([track, track])
    var snapshot = await store.snapshot()
    #expect(snapshot.entries.count == 2)
    #expect(snapshot.entries[0].trackID == snapshot.entries[1].trackID)
    #expect(snapshot.entries[0].id != snapshot.entries[1].id)

    try await store.apply(.remove([snapshot.entries[0].id]))
    let removedRevision = await store.snapshot().revision
    #expect(await store.snapshot().entries.count == 1)
    #expect(await store.undo())
    snapshot = await store.snapshot()
    #expect(snapshot.entries.count == 2)
    #expect(snapshot.revision > removedRevision)
}

@Test func removingPlayingEntryDoesNotStopPlaybackIdentity() async throws {
    let tracks = makeTracks(2)
    let store = ProductionQueueStore()
    await store.append(tracks)
    let playing = await store.snapshot().entries[0].id
    await store.commitPlaying(playing, generation: PlaybackGeneration(rawValue: 1))
    try await store.apply(.remove([playing]))
    let snapshot = await store.snapshot()
    #expect(!snapshot.entries.contains(where: { $0.id == playing }))
    #expect(snapshot.playingEntryID == playing)
    #expect(snapshot.tracks[tracks[0].id] != nil)
}

@Test func shuffleTraversalKeepsHistoryAndUsesDeterministicSeed() async throws {
    let tracks = makeTracks(5)
    let first = ProductionQueueStore(shuffleSeed: 42)
    let second = ProductionQueueStore(shuffleSeed: 42)
    await first.append(tracks)
    await second.append(tracks)
    try await first.apply(.setShuffle(true))
    try await second.apply(.setShuffle(true))

    let entries1 = await first.snapshot().entries
    let entries2 = await second.snapshot().entries
    var sequence1: [Int] = []
    var sequence2: [Int] = []
    var current1: QueueEntryID?
    var current2: QueueEntryID?
    for generation in 1...3 {
        let next1 = await first.proposedEntry(after: current1, direction: .forward, cause: .manual)
        let next2 = await second.proposedEntry(after: current2, direction: .forward, cause: .manual)
        #expect(next1 != nil)
        let index1 = entries1.firstIndex(where: { $0.id == next1 })!
        let index2 = entries2.firstIndex(where: { $0.id == next2 })!
        #expect(index1 == index2)
        await first.commitPlaying(next1, generation: PlaybackGeneration(rawValue: UInt64(generation)))
        await second.commitPlaying(next2, generation: PlaybackGeneration(rawValue: UInt64(generation)))
        sequence1.append(index1)
        sequence2.append(index2)
        current1 = next1
        current2 = next2
    }
    #expect(sequence1 == sequence2)
    #expect(Set(sequence1).count == sequence1.count)
    let previous = await first.proposedEntry(after: current1, direction: .backward, cause: .manual)
    #expect(entries1.firstIndex(where: { $0.id == previous }) == sequence1[1])
}

@Test func manualNextAdvancesWhileRepeatOneIsEnabled() async throws {
    let store = ProductionQueueStore()
    await store.append(makeTracks(2))
    let entries = await store.snapshot().entries
    try await store.apply(.setRepeat(.one))
    let proposed = await store.proposedEntry(after: entries[0].id, direction: .forward, cause: .manual)
    #expect(proposed == entries[1].id)
    let automatic = await store.proposedEntry(after: entries[0].id, direction: .forward, cause: .automaticEnd)
    #expect(automatic == entries[0].id)
}

@Test func staleGenerationCannotReplacePlayingEntry() async {
    let store = ProductionQueueStore()
    await store.append(makeTracks(2))
    let entries = await store.snapshot().entries
    await store.commitPlaying(entries[1].id, generation: PlaybackGeneration(rawValue: 8))
    await store.commitPlaying(entries[0].id, generation: PlaybackGeneration(rawValue: 7))
    #expect(await store.snapshot().playingEntryID == entries[1].id)
}

@Test func folderImportUsesNaturalOrderAndRetainsMetadataFailures() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let names = ["track10.mp3", "track2.mp3", "track1.mp3", "notes.txt", ".hidden.mp3"]
    for name in names { try Data().write(to: directory.appendingPathComponent(name)) }

    let importer = FileImportService(access: TestFileAccess(), metadataLoader: TestMetadataLoader())
    let result = await importer.importURLs([directory])
    #expect(result.failures.isEmpty)
    #expect(result.tracks.map { $0.lastKnownURL.lastPathComponent } == ["track1.mp3", "track2.mp3", "track10.mp3"])
    #expect(result.tracks.allSatisfy {
        if case .unavailable = $0.metadata { return true }
        return false
    })
}

@Test func missingImportIsReportedWithoutInventingAQueueItem() async {
    let missing = URL(fileURLWithPath: "/tmp/macamp-definitely-missing/file.mp3")
    let importer = FileImportService(access: TestFileAccess(), metadataLoader: TestMetadataLoader())
    let result = await importer.importURLs([missing])
    #expect(result.tracks.isEmpty)
    #expect(result.failures.count == 1)
}

@Test func staleBookmarkRequiresReauthorization() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let service = SecurityScopedFileAccessService(
        bookmarkCreator: { _ in Data([1]) },
        bookmarkResolver: { _ in BookmarkResolution(url: file, isStale: true) }
    )
    let track = TrackReference(lastKnownURL: file, securityScopedBookmark: Data([1]))
    let resolution = try await service.resolve(track)
    switch resolution {
    case .needsReauthorization(let url): #expect(url == file)
    case .granted: Issue.record("Stale bookmarks must not grant a lease")
    }
}

@Test func resolvedBookmarkGrantsAReusableReleaseSafeLease() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1, 2, 3]).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let acquisitions = LockedCounter()
    let releases = LockedCounter()
    let service = SecurityScopedFileAccessService(
        bookmarkCreator: { _ in Data([1, 2, 3]) },
        bookmarkResolver: { _ in BookmarkResolution(url: file, isStale: false) },
        requiresAcquiredSecurityScope: true,
        scopeAcquirer: { _ in acquisitions.increment(); return true },
        scopeReleaser: { _ in releases.increment() }
    )
    let bookmark = try await service.bookmark(for: file)
    let track = TrackReference(lastKnownURL: file, securityScopedBookmark: bookmark)
    switch try await service.resolve(track) {
    case .needsReauthorization:
        Issue.record("A fresh bookmark for an existing local file should resolve")
    case .granted(let lease):
        #expect(lease.url.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
        await lease.release()
        await lease.release()
        #expect(acquisitions.value == 1)
        #expect(releases.value == 1)
    }
}

@Test func deniedRequiredSecurityScopeNeedsReauthorizationWithoutRelease() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1]).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let releases = LockedCounter()
    let service = SecurityScopedFileAccessService(
        bookmarkCreator: { _ in Data([1]) },
        bookmarkResolver: { _ in BookmarkResolution(url: file, isStale: false) },
        requiresAcquiredSecurityScope: true,
        scopeAcquirer: { _ in false },
        scopeReleaser: { _ in releases.increment() }
    )

    let track = TrackReference(lastKnownURL: file, securityScopedBookmark: Data([1]))
    switch try await service.resolve(track) {
    case .needsReauthorization(let url): #expect(url == file)
    case .granted: Issue.record("Denied sandbox scope must not grant a lease")
    }
    #expect(releases.value == 0)
}

@Test func invalidScopedBookmarkFallsBackToReadablePathForLocalBuild() async throws {
    enum FixtureError: Error { case invalidBookmark }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1, 2, 3]).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let service = SecurityScopedFileAccessService(
        bookmarkCreator: { _ in Data([1]) },
        bookmarkResolver: { _ in throw FixtureError.invalidBookmark },
        allowsDirectFileAccessFallback: true
    )
    let track = TrackReference(lastKnownURL: file, securityScopedBookmark: Data([1]))

    switch try await service.resolve(track) {
    case .needsReauthorization:
        Issue.record("A readable local file should survive an invalidated development bookmark")
    case .granted(let lease):
        #expect(lease.url == file)
        await lease.release()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int { lock.withLock { storage } }

    func increment() {
        lock.withLock { storage += 1 }
    }
}

@Test func sessionStoreFallsBackAfterInterruptedOrCorruptPrimaryWrite() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("session.json")
    let store = AtomicSessionStore(fileURL: url)
    let track = makeTracks(1)[0]
    let entry = QueueEntry(trackID: track.id)
    let original = SessionState(queue: [entry], tracks: [track], currentEntryID: entry.id, position: 12)
    var newer = original
    newer.position = 27
    try await store.save(original)
    try await store.save(newer)

    try Data("{interrupted".utf8).write(to: url)
    let restored = try await store.load()
    #expect(restored == original)
    #expect((try Data(contentsOf: url)) == Data("{interrupted".utf8))
}

@Test func missingSessionReturnsNilAndRestoredPlaybackIsPaused() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AtomicSessionStore(fileURL: directory.appendingPathComponent("missing.json"))
    #expect(try await store.load() == nil)

    let track = makeTracks(1)[0]
    let entry = QueueEntry(trackID: track.id)
    let state = SessionState(queue: [entry], tracks: [track], currentEntryID: entry.id, position: 33)
    let playback = SessionRestoration.playbackSnapshot(from: state)
    #expect(playback.state == .paused)
    #expect(playback.position == 33)
    #expect(playback.currentEntryID == entry.id)
}

@Test func unsupportedSessionSchemaIsRejectedWithoutChangingTheFile() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("future.json")
    let original = try JSONEncoder().encode(SessionState(schemaVersion: 999))
    try original.write(to: url)
    let store = AtomicSessionStore(fileURL: url)
    do {
        _ = try await store.load()
        Issue.record("A future schema must not be guessed or migrated")
    } catch {
        #expect(error is SessionStoreError)
    }
    #expect(try Data(contentsOf: url) == original)
}

private func makeTracks(_ count: Int) -> [TrackReference] {
    (0..<count).map { TrackReference(lastKnownURL: URL(fileURLWithPath: "/tmp/track\($0).mp3")) }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacAmpTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private actor TestFileAccess: FileAccessService {
    func bookmark(for url: URL) -> Data { Data(url.path.utf8) }
    func resolve(_ track: TrackReference) -> FileAccessResolution {
        .needsReauthorization(lastKnownURL: track.lastKnownURL)
    }
}

private actor TestMetadataLoader: TrackMetadataLoading {
    enum Failure: Error { case malformed }
    func metadata(for url: URL) throws -> TrackMetadata { throw Failure.malformed }
}
