# MioAmp prototype report

Date: September 25, 2026

Artifact: `build/MioAmp.app` (local ad-hoc signature)

The prototype gate in `BUILD-PLAN.md` is complete. This is a development build, not a notarized public release or the full P0 MVP.

## Implemented vertical slice

- Native AppKit player, playlist, ten-band equalizer, and compact player windows.
- Snap/group/detach layout behavior, module menus, reset layout, and Dock reopen handling.
- Open/Add panels and drag/drop routing into a duplicate-safe queue.
- Native bounded PCM decoding and output for the prototype MP3, AAC/M4A, FLAC, and WAV matrix.
- Play, pause, stop, seek, previous/next, volume, shuffle/repeat, queue edits, EQ/preamp/bypass/reset, and gapless next-track staging.
- Atomic session state, security-scoped file leases, paused restoration, and bounded malformed-track traversal.
- Declarative Studio Graphite and Paper skins using one validated schema and original artwork; live switching with fallback recovery.
- Keyboard-focusable native controls and explicit accessibility labels, values, state text, and non-color playing/selection indicators.

## Automated evidence

`./scripts/test.sh` on Xcode 26.2 / Swift 6.2.3 / arm64 macOS 26 completed with 47 passing tests and zero failures. Five Core Audio graph tests are intentionally disabled in Swift Testing because parallel AudioComponent construction can abort the test host; the same compiled scenarios run serially through `AudioProbe`.

Audio probe evidence:

- Prototype formats decoded the expected 88,200 frames and sought successfully.
- WAV and tagged MP3 pairs rendered an exact 88,200-frame combined timeline without a silent hole.
- Bounded MP3 pair playback transitioned to the second track and ended.
- Rapid play/seek/pause/play/stop/restart with live EQ and volume completed without stale-generation failures.
- A requested +12 dB EQ gain measured +11.990 dB.
- A ten-minute VBR MP3 seek to 599.5 seconds returned a bounded read.

Packaging evidence:

- `./scripts/package-app.sh` produced `build/MioAmp.app`.
- `codesign --verify --deep --strict --verbose=2 build/MioAmp.app` passed.
- Studio Graphite, Paper, and the creator example are present under the app’s resources.

## Manual app evidence

The freshly packaged app was launched and inspected through the macOS accessibility tree and screenshots. Verified:

1. Player empty state exposes transport, disabled seek, volume, Open, EQ, List, and compact controls.
2. Equalizer exposes preamp and ten labeled bands with accessible dB values.
3. Playlist exposes search, row state, add/remove/reorder, shuffle, repeat, and track count.
4. Studio Graphite → Paper changes the live windows through the packaged skin resources.
5. Opening the generated WAV fixture through `NSOpenPanel` changed state to Playing, produced audio through the real engine, reached Stopped at end, and populated the playlist.
6. Compact mode presents play/pause, track information, time, and expand.

## Remaining MVP work

- Complete and test ALAC, HE-AAC/ADTS, Ogg Vorbis, and Ogg Opus; broaden corrupt/container fixtures and oldest-supported-OS coverage.
- Complete M3U/M3U8/PLS, named saved lists, 10,000-row performance, reauthorization/Locate UI, Finder document types, and system media/Now Playing integration.
- Add external `.mioampskin` import/export/remove, package resource limits, Terminal skin, accent editor, and creator round-trip validation.
- Persist shuffle/repeat/selection and full window/skin state with schema migration.
- Run the physical output/sleep/headphone, multi-display/Spaces, full VoiceOver, long-run performance, five-person usability, signing, notarization, and clean-Mac release gates.

