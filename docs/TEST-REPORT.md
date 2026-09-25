# ChuckAmp MVP candidate test report

Date: September 25, 2026  
Host: Apple silicon Mac mini, 16 GB  
OS/toolchain: macOS 26.5.2, Xcode 26.2, Swift 6.2.3  
Artifact: `build/ChuckAmp.app`, ad-hoc signed local candidate

## Automated results

- `./scripts/test.sh`: 76 passed, 0 failed; 5 AudioComponent-host cases intentionally skipped in the parallel Swift Testing host and covered by the serial probes below.
- 10,000-entry data measurement in the debug test: playlist parse and missing reporting 0.159 seconds; queue append plus search 0.037 seconds; combined under 0.25 seconds.
- `./scripts/package-app.sh`: release build succeeded and produced `build/ChuckAmp.app`.
- `codesign --verify --deep --strict --verbose=2 build/ChuckAmp.app`: valid on disk and satisfies its designated requirement.
- `plutil -lint build/ChuckAmp.app/Contents/Info.plist`: OK.
- Packaged resources contain Studio Graphite, Paper, Terminal, and CreatorExample. `otool -L` shows system frameworks only; ZIPFoundation is statically linked.

## Serial Core Audio results

The probes were run outside the command filesystem sandbox so macOS could load its codec and AudioComponent plug-ins.

- Bounded decode passed for AAC-LC/M4A, 192 kHz 24-bit FLAC, 24-bit ALAC, HE-AAC/ADTS, Ogg Vorbis, and Ogg Opus.
- Production engine stress ended at generation 12 with zero failure events.
- The tagged MP3 pair emitted a matching transition and end event.
- Corrupt input produced a typed `corrupt` failure at generation 21.
- The +12 dB overload probe predicted an unprotected peak of 3.583; the post-EQ limiter held captured output to 0.733.
- The hardware output graph started at 48 kHz stereo.

Expanded frame and boundary results are in `Tests/Fixtures/Audio/results-macos26.json` and `docs/AUDIO-FEASIBILITY.md`.

## Package and state coverage

- Portable playlists cover M3U/M3U8 import/export, PLS import, relative paths, duplicate order, UTF-8/Latin-1 handling, missing files, and unsupported remote entries.
- Session tests cover schema 1→2 migration, atomic backup recovery, queue policy restoration, and paused relaunch semantics.
- Skin tests cover preview/install/export/remove, creator and accent round trips, traversal, symlink, duplicate, corrupt image, file-count, compressed/expanded-byte, image-dimension, and decoded-memory rejection.
- Coordinator and UI tests cover Undo, partial-import notices, presentation persistence, layout recovery, scale/compact restoration, accessibility labels, queue state distinctions, and command routing.

## Not run

The Mac was locked during final visual automation, so the post-integration menu and layout smoke check was not rerun. The accepted prototype UI had already been visually exercised before this wave. macOS 14 codec behavior, VoiceOver, multi-display/Spaces behavior, removable-volume reauthorization, physical device disconnect/sleep-wake, long-run CPU/memory, five-participant usability, Developer ID signing, and notarization require environments, hardware, participants, or credentials not available in this run.
