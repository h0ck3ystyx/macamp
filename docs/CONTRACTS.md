# ChuckAmp shared contracts

Status: frozen for wave 1. Changes require coordinator review because audio, data, UI, and skin work all compile against these definitions.

## Build decisions

- Swift 6.2 language mode with strict concurrency checking supplied by the toolchain.
- macOS 14 minimum and Apple silicon prototype target.
- Swift Package Manager is the canonical build graph. Xcode opens `Package.swift` and generates the shared ChuckAmp scheme; `scripts/package-app.sh` creates the development app bundle. A generated `.xcodeproj` is deferred until distribution settings require one.
- AppKit owns lifecycle and modular windows. SwiftUI may be used later for settings or isolated content where it does not weaken window control.
- Foundation-only shared contracts prevent UI and audio frameworks from leaking across module boundaries.
- No external runtime dependencies were selected in T0.

## Ownership and state flow

The UI and Mac integrations emit `PlayerCommand` values. `PlaybackCoordinator` is the only component that translates those commands into queue and audio changes. Presentation reads immutable `PlaybackSnapshot` and `QueueSnapshot` values.

`QueueStore` owns visible order, selection, shuffle traversal history, repeat policy, Undo, and the proposed next entry. `updateTrack(_:)` refreshes an existing durable file reference while preserving entry identities and traversal state. Proposals include a `TraversalCause`: manual Next advances even under Repeat One, while an automatic end may repeat the current entry. `PlaybackCoordinator` stages that proposal with `AudioEngineClient`. The queue advances only after an engine transition event with the matching `PlaybackGeneration`. Old callbacks are ignored.

The same file may produce several `QueueEntry` values. A `TrackReference` carries source identity and an optional bookmark; its last-known URL is not proof of access. A resolved `FileAccessLease` stays alive for the decoder/prefetch lifetime and must be released on cancellation.

## Concurrency invariants

- UI-observable state is main-actor owned.
- Playback commands and audio events are serialized by the coordinator, outside the real-time render callback.
- Decoding, metadata parsing, bookmark resolution, and persistence do not block the main actor.
- A load or seek increments `PlaybackGeneration`; stale generation events cannot mutate active state.
- Cancelling prefetch releases its decoder, buffers, and file access lease.
- Unknown duration is `nil`; zero duration is a distinct measured value.
- Audio render code does not allocate UI objects, parse files, persist data, or wait on actors.

## Persistence and skin rules

`SessionState` is explicitly versioned. Schema 2 persists selection, shuffle, and repeat policy in addition to the queue, audio, skin, and window fields; schema-1 decoding supplies safe defaults before the Library store migrates it. Implementations write atomically and restore a previously playing session as paused. Migration failures preserve the old file for recovery.

`SkinManifest` is declarative data. `ResolvedSkin` contains validated local asset URLs only. A skin cannot define actions, network access, scripts, or audio behavior. View code consumes canonical style keys and must not special-case a bundled skin.

## Contract-change process

A worker reports the requested semantic change, affected task, migration/compatibility effect, and proposed test. The coordinator changes the shared definition and communicates the revision. Workers do not add look-alike types in feature modules.
