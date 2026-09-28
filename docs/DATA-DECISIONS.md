# Queue, file access, and session decisions

Status: T2 prototype plus T9 data implementation, September 25, 2026. Shared types remain defined by `docs/CONTRACTS.md`.

## Queue ownership

`ProductionQueueStore` is an actor and is the production implementation of `QueueStore`. A source (`TrackReference`) and an occurrence in the queue (`QueueEntry`) have separate identities, so adding one source twice creates two independently selectable and removable rows. Selection and playing identity are also separate. Removing the playing row removes it from future traversal but retains its track and `playingEntryID` until the playback coordinator commits another entry. This lets the current decoder finish without queue editing restarting audio.

All mutations increase the snapshot revision. Playback commits reject generations older than the most recently committed generation. Select, remove, move, shuffle, and repeat changes keep a bounded in-memory undo stack (50 states by default); `undo()` restores traversal state as well as visible order. Undo persistence is outside the prototype.

Linear traversal follows visible order. Repeat All wraps at either end. A manual Previous or Next ignores Repeat One, while an `automaticEnd` proposal returns the current entry. Shuffle uses a seeded SplitMix64 Fisher-Yates deck, visits each available entry once, and retains committed history so Previous follows what the listener actually heard. Repeat All creates a new deck after exhaustion and excludes the current entry when alternatives exist.

`search(_:limit:)` matches filename, title, artist, and album with case- and diacritic-insensitive comparison and returns queue-entry identities without changing selection. `revealURL(for:)` returns the last-known source URL for Finder Reveal or Locate UI, including when the file is currently missing. `updateTrack(_:)` installs a refreshed reference without changing queue-entry identities, playback identity, order, selection, or traversal.

## Portable and saved playlists

`PortablePlaylistCodec` imports M3U, M3U8, and PLS. M3U8 requires valid UTF-8. M3U and PLS prefer UTF-8 and fall back to ISO-8859-1 for legacy files. M3U comments and extended-info lines are ignored; PLS `FileN` values are ordered by their numeric suffix rather than physical line order. Relative paths resolve against the playlist's directory. Local entries retain source order and duplicates. Missing paths remain in the result for Locate while also producing a `missingLocalFile` issue. HTTP and other non-file URLs are excluded and reported as `unsupportedRemoteURL` issues.

M3U and M3U8 export writes UTF-8 with `#EXTM3U` and preserves input order. It uses relative paths for descendants of the destination directory when requested and absolute paths otherwise. PLS export is outside P0. `FileImportService` expands a selected M3U/M3U8/PLS file through this codec, reports remote entries as import failures, then applies the ordinary bookmark and metadata pipeline to local entries.

Parsing a playlist does not grant access to referenced files. In the sandbox, bookmark creation can still fail for sibling or removable-volume entries, which keeps the row out of the active import and provides an authorization failure for the UI. The user must select the file or an appropriate containing folder before playback can rely on a durable bookmark.

`SavedPlaylistStore` persists a versioned catalog atomically. Each named playlist is an ordered value snapshot of track references, so later active-queue edits never rewrite it. Duplicate occurrences are retained. Save, rename, and remove record a bounded Undo history; applying Undo writes the restored catalog before returning, so the result survives relaunch. The Undo stack itself is intentionally process-local.

## Import and metadata

`FileImportService` accepts files and folders. It recursively enumerates folders, skips hidden files and package descendants, filters the supported audio extensions, and sorts each folder using case-insensitive numeric comparison under `en_US_POSIX`; for example, `track2.mp3` precedes `track10.mp3`. Top-level selections retain the order supplied by Finder or the open panel.

Bookmark creation and metadata loading run asynchronously with at most eight candidates in flight. Task groups allow slow metadata reads to overlap while the indexed result merge preserves display order without creating an unbounded task set for a large folder. Metadata errors produce a queueable track with `.unavailable(reason:)`; missing files or authorization/bookmark failures produce an import failure and no invented row. `AVFoundationMetadataLoader` currently loads title, artist, album, and duration. Codec, sample rate, channels, track/disc numbers, and bounded artwork are follow-up metadata work.

Supported prototype discovery extensions are AAC, AIFF, ALAC, FLAC, M4A, MP3, MP4, OGA, OGG, Opus, and WAV. Extension discovery is only a candidate filter; decoder inspection remains authoritative.

## Security-scoped access

`SecurityScopedFileAccessService` stores security-scoped bookmarks and resolves them without UI. A missing file, stale bookmark, or resolution error returns `needsReauthorization` and preserves the last known URL for Locate/Reauthorize UI. Successful resolution returns a `SecurityScopedFileLease`. The decoder or prefetch owner must retain that lease for its whole lifetime and call `release()` on completion or cancellation. Release is actor-isolated and idempotent, so a granted scope is balanced at most once.

`reauthorize(_:at:)` verifies the located replacement exists, creates a fresh bookmark, and returns an updated reference with the same TrackID and metadata. Installing it through `ProductionQueueStore.updateTrack(_:)` preserves every QueueEntry ID, including duplicates of that source.

A last-known URL without bookmark data can be granted only when it still exists. This supports unsandboxed development builds but does not treat a path as durable sandbox authorization.

Unit tests inject bookmark creation and resolution because macOS may refuse creation for temporary files when tests run under SwiftPM's nested sandbox. The production bookmark APIs require a serial/manual probe from the sandboxed app using a file selected through `NSOpenPanel`; a synthetic temporary path cannot prove that authorization survives relaunch.

## Session durability and restoration

`AtomicSessionStore` encodes schema-versioned JSON with deterministic key order and uses Foundation's atomic file replacement. Before replacing an existing primary file it copies the last durable generation to `.backup`. Schema 2 persists queue order, current and selected entry, shuffle, repeat, position, volume, all EQ settings, skin, and window layout. Load validates schema, queue/track references, current/selected membership, finite position/volume/EQ values, skin identity, and window scale. If the primary cannot decode or validate, load attempts the backup without deleting or rewriting the failed primary, preserving evidence for recovery and migration debugging.

Schema 1 migrates to schema 3 in memory with no selection, shuffle off, repeat off, and default visualization settings. Schema 2 also migrates to schema 3 with default visualization settings. The next ordinary save writes schema 3 atomically; load alone leaves the original file untouched. The store rejects unknown schema versions rather than guessing a migration. A missing file loads as `nil`. A temporary artifact from an interrupted atomic write is ignored. If a damaged primary is visible after interruption, the prior backup remains loadable.

`SessionState` does not encode a playing/paused flag. `SessionRestoration.playbackSnapshot(from:)` maps a restored current entry to `.paused` and an empty session to `.idle`, preventing unsolicited playback after relaunch. Duration remains unknown until the decoder or metadata path supplies it.

`SessionRestoration.queueSnapshot(from:)` reconstructs queue identity, selection, current entry, shuffle, and repeat without generating new IDs. The playback coordinator remains responsible for creating a fresh shuffle deck from the restored policy; playback history is session-ephemeral.

## 10,000-entry measurement

On an Apple M4 Mac mini with 16 GB RAM running macOS 26.5.2, three debug runs measured a 10,000-line M3U8 parse with missing-path reporting at **0.149–0.189 seconds**, followed by actor-isolated append plus a filename search across a 10,000-entry queue at **0.039–0.041 seconds**. The complete performance test took **0.216–0.275 seconds**. Commands: `swift test --filter LibraryTests` and `./scripts/test.sh`. These are engineering measurements from one machine, not release-build latency claims; UI scrolling still depends on T5 virtualization.

## Integration notes

- Use `FileImportService.importURLs` for Open, Add, and drag/drop, then pass its tracks to `replace(with:)` or `append(_:)`.
- The same import entry point expands M3U, M3U8, and PLS. Surface `FileImportResult.failures` so unsupported remote entries and authorization failures are visible rather than silently dropped.
- Apply metadata results already embedded in imported tracks. Later incremental UI can insert pending tracks first and call `updateMetadata(trackID:metadata:)` as loads finish.
- The playback coordinator requests `.automaticEnd` traversal for an engine end event and `.manual` traversal for user commands, holds leases through decoder and prefetch lifetimes, and supplies monotonically increasing `PlaybackGeneration` values to `commitPlaying`.
- Persist `QueueSnapshot.entries`, selection, shuffle, repeat, and the tracks referenced by those entries. If the playing entry was removed during playback, persist no current entry because it no longer has a restorable queue identity; the durable queue itself remains intact. Restore queue and playback through `SessionRestoration` before publishing the first snapshots.
