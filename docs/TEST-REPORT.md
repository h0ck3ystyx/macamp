# MacAmp MVP candidate test report

Date: September 27, 2026
Host: Apple silicon Mac mini, 16 GB  
OS/toolchain: macOS 26.5.2, Xcode 26.2, Swift 6.2.3  
Artifact: `build/MacAmp.app`, ad-hoc signed local candidate

## Automated results

- `./scripts/test.sh`: 93 passed, 0 failed; 5 AudioComponent-host cases intentionally skipped in the parallel Swift Testing host and covered by the serial probes below.
- 10,000-entry data measurement in the debug test: playlist parse and missing reporting 0.159 seconds; queue append plus search 0.037 seconds; combined under 0.25 seconds.
- `./scripts/package-app.sh`: release build succeeded and produced `build/MacAmp.app`.
- `codesign --verify --deep --strict --verbose=2 build/MacAmp.app`: valid on disk and satisfies its designated requirement.
- `plutil -lint build/MacAmp.app/Contents/Info.plist`: OK.
- Packaged resources contain Studio Graphite, Paper, Terminal, and CreatorExample. `otool -L` shows system frameworks only; ZIPFoundation is statically linked.

## Serial Core Audio results

The probes were run outside the command filesystem sandbox so macOS could load its codec and AudioComponent plug-ins.

- Bounded decode passed for AAC-LC/M4A, 192 kHz 24-bit FLAC, 24-bit ALAC, HE-AAC/ADTS, Ogg Vorbis, and Ogg Opus.
- September 27 regression: the current Core Audio build returned `fmt?` while configuring Float32 output for both bundled and user-library FLAC files. The pinned `dr_flac` path decoded the affected 25 MB, 8,773,160-frame library track completely in 2.88 seconds and restored bounded reads and seeks for 16/24-bit FLAC.
- Sample-rate timing regression: the one-second 192 kHz FLAC took 4.65 seconds when its player lane inherited a 48 kHz graph format. With explicit source-rate lane formats it took 1.52 seconds including engine startup; the two-second 44.1 kHz fixture took 2.27 seconds. Mixed 44.1→192 kHz and 192→44.1 kHz pairs both transitioned and ended in 3.24 seconds.
- Production engine stress ended at generation 12 with zero failure events.
- The tagged MP3 pair emitted a matching transition and end event.
- Corrupt input produced a typed `corrupt` failure at generation 21.
- The +12 dB overload probe predicted an unprotected peak of 3.583; the post-EQ limiter held captured output to 0.733.
- The hardware output graph started at 48 kHz stereo.

Expanded frame and boundary results are in `Tests/Fixtures/Audio/results-macos26.json` and `docs/AUDIO-FEASIBILITY.md`.

## Package and state coverage

- Portable playlists cover M3U/M3U8 import/export, PLS import, relative paths, duplicate order, UTF-8/Latin-1 handling, missing files, and unsupported remote entries.
- Session tests cover schema 1→2 migration, atomic backup recovery, queue policy restoration, paused relaunch semantics, and non-destructive ChuckAmp-to-MacAmp Application Support migration.
- Skin tests cover preview/install/export/remove, creator and accent round trips, traversal, symlink, duplicate, corrupt image, file-count, compressed/expanded-byte, image-dimension, and decoded-memory rejection.
- Coordinator and UI tests cover Undo, clearing the queue, partial-import notices, presentation persistence, layout recovery, resized-frame preservation, scale/compact restoration, scaled typography, attached-window reflow, explicit skin control styling, accessibility labels and values, focus order, valid-action states, queue state distinctions, and command routing.
- Bundled-skin tests enforce 4.5:1 contrast for primary text, secondary text, and accents on both app backgrounds. Increase Contrast replaces secondary and border colors with primary text color.
- File-access tests cover strict sandbox authorization and the readable-path recovery used when an ad-hoc development rebuild invalidates an older scoped bookmark.

## Interactive smoke result

With the Mac unlocked, the rebuilt app restored the existing nine-item queue. Playing the selected fixture advanced into a previously saved MP3 from Downloads, confirming that the old invalidated bookmark recovered through readable local access. The playlist displayed its new accessible `CLR` control, and playback was stopped normally afterward.

The live UI matrix exercised Studio Graphite, Paper, and Terminal at 100%, 125%, and 150%. Each skin retained identical module geometry at a given scale; controls, typography, and hit targets enlarged with the interface, and the three attached windows remained flush. Focused captures confirmed usable contrast for every skin, including Studio Graphite’s transport, utility, and playlist controls.

The playlist was enlarged to 650 × 520 points. Selection, a one-result search, clearing the search, compact/expanded player transitions, and a quit/relaunch cycle all retained that exact size. Closing the equalizer through its title-bar close control moved the attached playlist up by the equalizer height; reopening it restored the three-window stack.

After follow-up testing, the default stack was rebalanced at every scale to give the equalizer 40 additional content points while keeping the total stack height unchanged. Restored frames are clamped to the current module minimums so legacy undersized equalizer layouts recover automatically.

The September 27 accessibility pass inspected the packaged app through the macOS AX tree. The player exposed dynamic Play/Pause, elapsed/total seek time, volume percent, and state-aware transport controls; the equalizer exposed preamp plus all ten bands with signed decibel values; the playlist exposed its search, table, and valid mutation controls. Space toggled Play/Pause with the seek slider focused and returned to the original state on the second press. The detailed release checklist is in `docs/ACCESSIBILITY-CHECKLIST.md`.

The packaged FLAC-fallback build restored the saved external-volume queue and played `08 - Socialite` as `FLAC · 44.1 kHz · Stereo`. Its live position advanced from 00:09 to 00:12 during a three-second AX observation, after which playback stopped normally.

## Not run

macOS 14 codec behavior, a complete VoiceOver audit, multi-display/Spaces behavior, removable-volume reauthorization, physical device disconnect/sleep-wake, long-run CPU/memory, five-participant usability, Developer ID signing, and notarization require environments, hardware, participants, or credentials not available in this run.
