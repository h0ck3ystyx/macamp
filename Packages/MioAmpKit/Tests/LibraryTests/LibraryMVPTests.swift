import Contracts
import Foundation
import Library
import Testing

@Test func m3uImportsRelativeAbsoluteAndReportsRemoteAndMissingEntries() throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("01 First.mp3")
    let nestedDirectory = directory.appendingPathComponent("disc2", isDirectory: true)
    let second = nestedDirectory.appendingPathComponent("02.flac")
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data().write(to: first)
    try Data().write(to: second)
    let text = """
    #EXTM3U
    #EXTINF:1,First
    01 First.mp3
    disc2/02.flac
    https://example.com/live.mp3
    missing.wav
    """

    let result = try PortablePlaylistCodec().decode(
        Data(text.utf8),
        format: .m3u8,
        relativeTo: directory
    )
    #expect(result.localURLs == [first, second, directory.appendingPathComponent("missing.wav")])
    #expect(result.issues.map(\.kind) == [.unsupportedRemoteURL, .missingLocalFile])
    #expect(result.issues.map(\.line) == [5, 6])
}

@Test func m3uAcceptsLegacyLatin1WhileM3U8RequiresUTF8() throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("café.mp3")
    try Data().write(to: file)
    let latin1 = Data([0x63, 0x61, 0x66, 0xE9, 0x2E, 0x6D, 0x70, 0x33, 0x0A])
    let imported = try PortablePlaylistCodec().decode(latin1, format: .m3u, relativeTo: directory)
    #expect(imported.localURLs == [file])
    #expect(imported.issues.isEmpty)
    #expect(throws: PortablePlaylistError.unreadableEncoding) {
        try PortablePlaylistCodec().decode(latin1, format: .m3u8, relativeTo: directory)
    }
}

@Test func plsUsesNumericFileOrderAndReportsRemoteEntries() throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("one.mp3")
    let second = directory.appendingPathComponent("two.mp3")
    try Data().write(to: first)
    try Data().write(to: second)
    let source = """
    [playlist]
    File2=two.mp3
    Title2=Two
    File3=http://example.com/radio
    File1=one.mp3
    NumberOfEntries=3
    Version=2
    """
    let result = try PortablePlaylistCodec().decode(Data(source.utf8), format: .pls, relativeTo: directory)
    #expect(result.localURLs == [first, second])
    #expect(result.issues.map(\.kind) == [.unsupportedRemoteURL])
}

@Test func exportedM3UAndM3U8RoundTripOrderWithRelativePaths() throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let audioDirectory = directory.appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    let urls = [audioDirectory.appendingPathComponent("b.mp3"), audioDirectory.appendingPathComponent("a.mp3")]
    for url in urls { try Data().write(to: url) }
    let codec = PortablePlaylistCodec()
    for extensionName in ["m3u", "m3u8"] {
        let destination = directory.appendingPathComponent("mix.\(extensionName)")
        try codec.exportM3U(urls: urls, to: destination)
        let bytes = try Data(contentsOf: destination)
        #expect(String(data: bytes, encoding: .utf8)?.contains("audio/b.mp3") == true)
        let imported = try codec.importPlaylist(at: destination)
        #expect(imported.localURLs == urls)
        #expect(imported.issues.isEmpty)
    }
}

@Test func fileImporterExpandsPlaylistInOrderAndReportsRemoteEntry() async throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("first.mp3")
    let second = directory.appendingPathComponent("second.flac")
    try Data().write(to: first)
    try Data().write(to: second)
    let playlist = directory.appendingPathComponent("album.m3u8")
    try Data("second.flac\nhttps://example.com/live\nfirst.mp3\n".utf8).write(to: playlist)
    let importer = FileImportService(access: MVPFileAccess(), metadataLoader: MVPMetadataLoader())
    let result = await importer.importURLs([playlist])
    #expect(result.tracks.map(\.lastKnownURL) == [second, first])
    #expect(result.failures.count == 1)
    #expect(result.failures[0].reason.contains("Unsupported remote playlist entry"))
}

@Test func savedPlaylistIsIndependentFromQueueAndUndoIsPersisted() async throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("playlists.json")
    let tracks = mvpTracks(3)
    let queue = ProductionQueueStore()
    await queue.append(tracks)
    let store = SavedPlaylistStore(fileURL: fileURL)
    let saved = try await store.save(name: "Road Trip", queue: await queue.snapshot())

    try await queue.apply(.remove([await queue.snapshot().entries[0].id]))
    #expect(try await store.all().first?.tracks == tracks)
    try await store.rename(saved.id, to: "Changed")
    #expect(try await store.all().first?.name == "Changed")
    #expect(try await store.undo())
    #expect(try await store.all().first?.name == "Road Trip")

    let relaunched = SavedPlaylistStore(fileURL: fileURL)
    #expect(try await relaunched.all().first?.name == "Road Trip")
    #expect(try await relaunched.all().first?.tracks == tracks)
}

@Test func queueSearchAndRevealUseMetadataAndFilenameWithoutMutatingSelection() async throws {
    let first = TrackReference(
        lastKnownURL: URL(fileURLWithPath: "/Volumes/Music/01-intro.mp3"),
        metadata: .loaded(TrackMetadata(title: "Résumé", artist: "The Band", album: "Live"))
    )
    let second = TrackReference(lastKnownURL: URL(fileURLWithPath: "/Volumes/Music/Finale.flac"))
    let store = ProductionQueueStore()
    await store.append([first, second])
    let entries = await store.snapshot().entries
    try await store.apply(.select(entries[1].id))

    #expect(await store.search("resume") == [entries[0].id])
    #expect(await store.search("final") == [entries[1].id])
    #expect(await store.search("music", limit: 0).isEmpty)
    #expect(await store.revealURL(for: entries[1].id) == second.lastKnownURL)
    #expect(await store.snapshot().selectedEntryID == entries[1].id)
}

@Test func reauthorizationPreservesTrackIdentityAndMetadata() async throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let replacement = directory.appendingPathComponent("located.mp3")
    try Data().write(to: replacement)
    let metadata = MetadataState.loaded(TrackMetadata(title: "Found"))
    let original = TrackReference(
        lastKnownURL: URL(fileURLWithPath: "/Volumes/Missing/lost.mp3"),
        securityScopedBookmark: Data([0]),
        metadata: metadata
    )
    let service = SecurityScopedFileAccessService(
        bookmarkCreator: { Data($0.path.utf8) },
        bookmarkResolver: { _ in BookmarkResolution(url: replacement, isStale: false) }
    )
    let updated = try await service.reauthorize(original, at: replacement)
    #expect(updated.id == original.id)
    #expect(updated.lastKnownURL == replacement)
    #expect(updated.metadata == metadata)
    #expect(updated.securityScopedBookmark == Data(replacement.path.utf8))
    let queue = ProductionQueueStore()
    await queue.append([original, original])
    let entryIDs = await queue.snapshot().entries.map(\.id)
    try await queue.updateTrack(updated)
    #expect(await queue.snapshot().entries.map(\.id) == entryIDs)
    #expect(await queue.snapshot().tracks[original.id] == updated)
    if case .granted(let lease) = try await service.resolve(updated) {
        await lease.release()
    } else {
        Issue.record("The refreshed reference should resolve")
    }
}

@Test func historicalSessionMigratesQueuePolicyAndVisualizationDefaults() async throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("session.json")
    let track = mvpTracks(1)[0]
    let entry = QueueEntry(trackID: track.id)
    let legacy = SessionState(
        schemaVersion: 1,
        queue: [entry],
        tracks: [track],
        currentEntryID: entry.id,
        position: 7,
        volume: 0.4,
        skinID: "paper",
        windowLayout: WindowLayout(scale: 1.5, isCompact: true)
    )
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    object.removeValue(forKey: "selectedEntryID")
    object.removeValue(forKey: "isShuffled")
    object.removeValue(forKey: "repeatMode")
    object.removeValue(forKey: "visualization")
    try JSONSerialization.data(withJSONObject: object).write(to: fileURL)

    let store = AtomicSessionStore(fileURL: fileURL)
    let migrated = try #require(try await store.load())
    #expect(migrated.schemaVersion == 3)
    #expect(migrated.selectedEntryID == nil)
    #expect(!migrated.isShuffled)
    #expect(migrated.repeatMode == .off)
    #expect(migrated.visualization == VisualizationSettings())

    var current = migrated
    current.selectedEntryID = entry.id
    current.isShuffled = true
    current.repeatMode = .all
    current.equalizer = EQSettings(isBypassed: false, preampGain: -2, bandGains: Array(repeating: 1, count: 10))
    try await store.save(current)
    let restored = try #require(try await store.load())
    #expect(restored == current)
    let queue = SessionRestoration.queueSnapshot(from: restored)
    #expect(queue.selectedEntryID == entry.id)
    #expect(queue.playingEntryID == entry.id)
    #expect(queue.isShuffled)
    #expect(queue.repeatMode == .all)
    #expect(SessionRestoration.playbackSnapshot(from: restored).state == .paused)
}

@Test func schemaTwoSessionMigratesVisualizationDefaults() async throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("session.json")
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(SessionState())) as? [String: Any])
    object["schemaVersion"] = 2
    object.removeValue(forKey: "visualization")
    try JSONSerialization.data(withJSONObject: object).write(to: fileURL)
    let migrated = try #require(try await AtomicSessionStore(fileURL: fileURL).load())
    #expect(migrated.schemaVersion == 3)
    #expect(migrated.visualization == VisualizationSettings())
}

@Test func tenThousandEntryPlaylistAndQueueStayWithinInteractiveImportBudget() async throws {
    let directory = try mvpTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = (0..<10_000).map { "track\($0).mp3" }.joined(separator: "\n")
    let clock = ContinuousClock()
    let parseStart = clock.now
    let parsed = try PortablePlaylistCodec().decode(Data(source.utf8), format: .m3u8, relativeTo: directory)
    let parseDuration = parseStart.duration(to: clock.now)
    #expect(parsed.localURLs.count == 10_000)
    #expect(parsed.issues.count == 10_000)
    #expect(parseDuration < .seconds(5))

    let queue = ProductionQueueStore()
    let tracks = mvpTracks(10_000)
    let queueStart = clock.now
    await queue.append(tracks)
    let matches = await queue.search("track9999")
    let queueDuration = queueStart.duration(to: clock.now)
    #expect(await queue.snapshot().entries.count == 10_000)
    #expect(matches.count == 1)
    #expect(queueDuration < .seconds(5))
    print("MioAmp 10k performance: playlist parse \(parseDuration), queue append+search \(queueDuration)")
}

private func mvpTracks(_ count: Int) -> [TrackReference] {
    (0..<count).map { TrackReference(lastKnownURL: URL(fileURLWithPath: "/tmp/track\($0).mp3")) }
}

private func mvpTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MioAmpMVPTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private actor MVPFileAccess: FileAccessService {
    func bookmark(for url: URL) -> Data { Data(url.path.utf8) }
    func resolve(_ track: TrackReference) -> FileAccessResolution {
        .needsReauthorization(lastKnownURL: track.lastKnownURL)
    }
    func reauthorize(_ track: TrackReference, at url: URL) -> TrackReference {
        TrackReference(id: track.id, lastKnownURL: url, securityScopedBookmark: Data(url.path.utf8), metadata: track.metadata)
    }
}

private actor MVPMetadataLoader: TrackMetadataLoading {
    func metadata(for url: URL) -> TrackMetadata { TrackMetadata(title: url.deletingPathExtension().lastPathComponent) }
}
