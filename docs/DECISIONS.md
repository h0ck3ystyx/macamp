# Decision log

## D-001 — Canonical build graph

Use Swift Package Manager for the prototype foundation and open `Package.swift` directly in Xcode. This gives each feature an explicit target, makes command-line builds reproducible, and avoids maintaining a handwritten project file. The package script creates the `.app` bundle. Revisit a generated Xcode project when entitlements, archive, or distribution workflows require it.

## D-002 — Swift and concurrency

Use Swift 6.2 and its strict concurrency model. Shared values are `Sendable`; mutable services are expected to be actors or otherwise prove synchronization. Main-actor UI state is separate from the playback coordinator and real-time audio work.

## D-003 — Dependency threshold

T0 adds no third-party dependencies. Audio and archive spikes must demonstrate an actual platform gap, document license/provenance, and request the narrowest dependency that fills it.

## D-004 — Prototype truthfulness

The foundation exposes no playback-looking controls. Later UI hides unfinished optional behavior. Playback position comes from the audio path, skin changes flow through public skin data, and tests distinguish simulated service behavior from actual media evidence.

