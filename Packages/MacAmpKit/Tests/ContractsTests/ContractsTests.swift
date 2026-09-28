import Contracts
import Foundation
import TestSupport
import Testing

@Test func duplicateTrackReferencesProduceDistinctQueueEntries() async {
    let store = FakeQueueStore()
    let track = TrackReference(lastKnownURL: URL(fileURLWithPath: "/tmp/example.mp3"))

    await store.append([track, track])
    let snapshot = await store.snapshot()

    #expect(snapshot.entries.count == 2)
    #expect(snapshot.entries[0].trackID == snapshot.entries[1].trackID)
    #expect(snapshot.entries[0].id != snapshot.entries[1].id)
}

@Test func sessionStateRoundTripsAndKeepsUnknownDurationDistinctFromZero() throws {
    let track = TrackReference(lastKnownURL: URL(fileURLWithPath: "/tmp/example.flac"))
    let entry = QueueEntry(trackID: track.id)
    let state = SessionState(queue: [entry], tracks: [track], currentEntryID: entry.id, position: 0)

    let encoded = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(SessionState.self, from: encoded)

    #expect(decoded == state)
    #expect(decoded.tracks[0].metadata == .pending)
}

@Test func visualizationSettingsRoundTripWithSessionSchemaThree() throws {
    var settings = VisualizationSettings()
    settings.presetID = "builtin.phosphor"
    settings.favoritePresetIDs = ["builtin.phosphor"]
    settings.quality = .high
    let state = SessionState(visualization: settings)
    let decoded = try JSONDecoder().decode(SessionState.self, from: JSONEncoder().encode(state))
    #expect(decoded.schemaVersion == 3)
    #expect(decoded.visualization == settings)
    #expect(PlayerModule.allCases.contains(.visualization))
}

@Test func equalizerRequiresAndProvidesTenBands() {
    let equalizer = EQSettings()
    #expect(equalizer.bandGains.count == 10)
    #expect(EQSettings.frequencies.count == 10)
}
