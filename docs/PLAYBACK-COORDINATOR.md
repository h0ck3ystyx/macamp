# Playback coordinator

`ProductionPlaybackCoordinator` is the sole serial owner of transport decisions. Menu, Finder, and player UI actions send the shared `PlayerCommand`; the coordinator mutates the queue, prepares the audio graph, and publishes revisioned `PlaybackSnapshot` values.

## Production assembly

Create the durable store at the Application Support session URL and await production assembly before attaching UI observers:

```swift
let store = AtomicSessionStore(fileURL: sessionURL)
let playback = try await ProductionPlaybackCoordinator.makeProduction(sessionStore: store)
```

The factory loads the session before constructing `ProductionQueueStore`, preserving queue-entry identities. Its first snapshot is idle for a new session or paused for a restored current item. Audio resources are acquired lazily when the user presses Play, so relaunch cannot unexpectedly produce sound.

The production graph uses `FileImportService`, `SecurityScopedFileAccessService`, `NativeAudioDecoder`, and `NativeAudioEngineClient`. Tests inject the same shared contracts plus the narrow `PlaybackURLImporting` and decoder-factory adapters, keeping hardware out of deterministic state-machine tests.

## Generations and ownership

Every current load, seek, and staged successor receives a monotonically increasing `PlaybackGeneration`. Current callbacks must match the current entry and generation; transition callbacks must match the staged entry and generation. Everything else is ignored. A directly selected or manually traversed item is committed after `prepare` succeeds; a prefetched item is committed only on its matching engine `transitioned` event.

The coordinator retains a security-scoped lease for the current decoder and a second lease for prefetched audio. Replacing playback, editing traversal state, cancelling prefetch, failing a preparation, or transitioning releases the corresponding lease. Queue edits restage the successor without restarting the current decoder.

Manual Previous and Next use `.manual`; end-of-file and prefetch use `.automaticEnd`. This preserves Repeat One behavior while allowing a user to leave the repeated track. Previous seeks to zero after three seconds.

Unreadable candidates are skipped with a set of attempted queue occurrences. A load or prefetch never examines more than one queue traversal, including Repeat All and shuffle, so malformed files cannot create an infinite loop. Exhaustion publishes a failure.

## Persistence

Queue and playback changes are saved through the injected `SessionStore`. Skin and window fields loaded from the session are preserved. If a playing row has been removed, its ID is omitted from durable state because it cannot be restored into the queue. Persistence errors do not interrupt audio; a later state change retries the write.

App composition should retain one coordinator for the process and pass that same instance to windows, menus, Finder-open routing, and future media-key integration. It should not instantiate a second engine or translate transport commands elsewhere.

Presentation consumes `snapshots` for playback state and calls `await playback.queueSnapshot()` after a playback revision or queue command to obtain the current `QueueSnapshot`. This keeps the production queue private to the coordinator while giving the UI both frozen presentation values.
