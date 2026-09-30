# MacAmp MVP candidate test report

Date: September 29, 2026
Host: Apple silicon Mac mini, 16 GB  
OS/toolchain: macOS 26.5.2, Xcode 26.2, Swift 6.2.3  
Artifact: `build/MacAmp.app`, ad-hoc signed local candidate

## Automated results

- `./scripts/test.sh`: 112 passed, 0 failed; 5 AudioComponent-host cases intentionally skipped in the parallel Swift Testing host and covered by the serial probes below.
- 10,000-entry data measurement in the debug test: playlist parse and missing reporting 0.171 seconds; queue append plus search 0.040 seconds; combined under 0.25 seconds.
- `./scripts/package-app.sh`: release build succeeded and produced `build/MacAmp.app`.
- `codesign --verify --deep --strict --verbose=2 build/MacAmp.app`: valid on disk and satisfies its designated requirement.
- `plutil -lint build/MacAmp.app/Contents/Info.plist`: OK.
- Packaged resources contain Studio Graphite, Paper, Terminal, and CreatorExample. `otool -L` shows system frameworks only; ZIPFoundation is statically linked.
- `./scripts/validate-app-bundle.sh`: the ad-hoc development bundle contains valid App Sandbox, user-selected read/write, and app-scoped bookmark entitlements plus its privacy manifest, compiled app icon, and release resources. Validation also checks version/build, linked libraries, expected architectures, and embedded test/debug artifacts.
- `./scripts/archive-app-store.sh`: Xcode 26.2 produced `/tmp/MacAmp-AppStore.xcarchive`; its 1.0.0 (1) unsigned application passed structural validation and contains a universal `arm64`/`x86_64` executable. App Store distribution signing and delivery validation remain pending the final App ID and authorized profile.
- Release binary audit found system libraries only, no embedded test/debug artifacts, no URL endpoint or local source path strings, and one executable. The statically linked ZIPFoundation resource bundle includes its own no-collection privacy manifest and declares its user-selected file timestamp access reason.
- The release host has zero valid code-signing identities, so an Apple Distribution archive cannot be produced until the account holder installs authorized credentials.
- A first parallel run exposed a fatal Metal-unavailable initializer. The renderer now presents an accessible nonfatal fallback when device, command queue, shader compilation, or pipeline setup is unavailable; the complete 106-test rerun passed.

## Serial Core Audio results

The probes were run outside the command filesystem sandbox so macOS could load its codec and AudioComponent plug-ins.

- Bounded decode passed for AAC-LC/M4A, 192 kHz 24-bit FLAC, 24-bit ALAC, HE-AAC/ADTS, Ogg Vorbis, and Ogg Opus.
- September 27 regression: the current Core Audio build returned `fmt?` while configuring Float32 output for both FLAC and all eight MP3 files in a bounded real-library sample. Pinned `dr_flac` and `dr_mp3` paths restore bounded reads and seeks, including ID3-prefixed FLAC and ID3-tagged MP3.
- Sample-rate timing regression: the one-second 192 kHz FLAC took 4.65 seconds when its player lane inherited a 48 kHz graph format. With explicit source-rate lane formats it took 1.52 seconds including engine startup; the two-second 44.1 kHz fixture took 2.27 seconds. Mixed 44.1→192 kHz and 192→44.1 kHz pairs both transitioned and ended in 3.24 seconds.
- High-rate buffering now scales blocks to 250 ms and keeps thirty-two scheduled buffers, providing eight seconds per current/prefetched track at both 44.1 and 192 kHz. A policy regression test enforces 11,025-frame blocks at 44.1 kHz and 48,000-frame blocks at 192 kHz; the small-buffer engine stress probe remains independently configurable.
- Network-volume soaks reached 12 seconds for 44.1/96/192 kHz FLAC and 44.1 kHz MP3. Unified logging caught slow reads of 0.317 seconds at 96 kHz and 0.564 seconds at 192 kHz, while the eight-second queue recorded no low-water or underrun event. The inventory, decode timings, and limits are in `docs/NETWORK-AUDIO-REPORT.md`.
- A full-volume follow-up inspected 9,814 audio entries across 420.76 GiB and fully decoded all 1,403 readable MP3 files (10.0 GiB) with zero decoder failures. It added 32/48 kHz MP3, 48/88.2 kHz FLAC, PCM WAV, four-second, 76-minute, 712 MB, untagged, and Unicode-path cases. Legacy MP3 frame estimates can exceed decoded output by up to 1,152 frames; that narrow gapless limitation is documented rather than hidden.
- Refill accounting refreshes shared playback counters after every suspended decoder read. This prevents a slow network read from overwriting buffer-completion callbacks that arrived while the actor was suspended. The 192 kHz seek/pause/restart stress probe ended at generation 12 with zero failures after the change.
- Production engine stress ended at generation 12 with zero failure events.
- The tagged MP3 pair emitted a matching transition and end event.
- Corrupt input produced a typed `corrupt` failure at generation 21.
- The +12 dB overload probe predicted an unprotected peak of 3.583; the post-EQ limiter held captured output to 0.733.
- The hardware output graph started at 48 kHz stereo.

Expanded frame and boundary results are in `Tests/Fixtures/Audio/results-macos26.json` and `docs/AUDIO-FEASIBILITY.md`.

## Package and state coverage

- Visualization foundation tests cover schema-3 round trips, schema-1/schema-2 migration defaults, six distinct built-in preset identities, silence floor, 1 kHz band placement, antiphase stereo power, −6 dB level response, and sequence-gap history reset. The real audio tap, Metal rendering, and visible controls are not implemented at this checkpoint.
- Portable playlists cover M3U/M3U8 import/export, PLS import, relative paths, duplicate order, UTF-8/Latin-1 handling, missing files, and unsupported remote entries.
- Session tests cover schema 1→2 migration, atomic backup recovery, queue policy restoration, paused relaunch semantics, and non-destructive ChuckAmp-to-MacAmp Application Support migration.
- Skin tests cover preview/install/export/remove, creator and accent round trips, traversal, symlink, duplicate, corrupt image, file-count, compressed/expanded-byte, image-dimension, and decoded-memory rejection.
- Coordinator and UI tests cover Undo, clearing the queue, partial-import notices, presentation persistence, layout recovery, resized-frame preservation, scale/compact restoration, scaled typography, attached-window reflow, explicit skin control styling, accessibility labels and values, focus order, valid-action states, queue state distinctions, and command routing.
- Playlist rows support native local drag-and-drop reordering through the same persisted, Undo-aware move command as the arrow controls; invalid and no-op destinations are rejected, and reordering is disabled while search filtering makes the full order ambiguous.
- Playback commands remain ordered across actor suspension: a held seek must finish before following Pause and Play commands reach the engine. The progress slider commits one seek at drag completion to avoid redundant decoder churn.
- Playback ticks do not overwrite the progress thumb while the user is dragging it; normal playback-driven slider updates resume when tracking ends.
- Bundled-skin tests enforce 4.5:1 contrast for primary text, secondary text, and accents on both app backgrounds. Increase Contrast replaces secondary and border colors with primary text color.
- File-access tests cover strict sandbox authorization, readable-path recovery used when an ad-hoc development rebuild invalidates an older scoped bookmark, denied scope acquisition, and exactly-once release of acquired security scope across repeated cleanup.
- FLAC metadata falls back to a bounded native Vorbis-comment reader when AVFoundation omits title, artist, or album tags; the parser is covered by a synthetic tagged FLAC metadata block.

## Interactive smoke result

The September 29 sandbox checkpoint launched the entitlement-signed development bundle. It restored a saved FLAC at 02:21, changed from Paused to Playing, advanced normally to 02:36, and returned to Paused without asking the user to select the file again. This proves the basic persisted-bookmark path under App Sandbox; the complete export, stale bookmark, and network-volume disconnect matrix is still required.

With the Mac unlocked, the rebuilt app restored the existing nine-item queue. Playing the selected fixture advanced into a previously saved MP3 from Downloads, confirming that the old invalidated bookmark recovered through readable local access. The playlist displayed its new accessible `CLR` control, and playback was stopped normally afterward.

The live UI matrix exercised Studio Graphite, Paper, and Terminal at 100%, 125%, and 150%. Each skin retained identical module geometry at a given scale; controls, typography, and hit targets enlarged with the interface, and the three attached windows remained flush. Focused captures confirmed usable contrast for every skin, including Studio Graphite’s transport, utility, and playlist controls.

The playlist was enlarged to 650 × 520 points. Selection, a one-result search, clearing the search, compact/expanded player transitions, and a quit/relaunch cycle all retained that exact size. Closing the equalizer through its title-bar close control moved the attached playlist up by the equalizer height; reopening it restored the three-window stack.

After follow-up testing, the default stack was rebalanced at every scale to give the equalizer 40 additional content points while keeping the total stack height unchanged. Restored frames are clamped to the current module minimums so legacy undersized equalizer layouts recover automatically.

The September 27 accessibility pass inspected the packaged app through the macOS AX tree. The player exposed dynamic Play/Pause, elapsed/total seek time, volume percent, and state-aware transport controls; the equalizer exposed preamp plus all ten bands with signed decibel values; the playlist exposed its search, table, and valid mutation controls. Space toggled Play/Pause with the seek slider focused and returned to the original state on the second press. The detailed release checklist is in `docs/ACCESSIBILITY-CHECKLIST.md`.

The packaged FLAC-fallback build restored the saved external-volume queue and played `08 - Socialite` as `FLAC · 44.1 kHz · Stereo`. Its live position advanced from 00:09 to 00:12 during a three-second AX observation, after which playback stopped normally.

The September 29 seek regression check used the freshly packaged sandbox build and the ten-minute VBR MP3 fixture. Clicking the progress slider moved active playback to 05:00 while remaining `PLAYING`; Pause changed it to `PAUSED`, and Play returned it to `PLAYING` without a stale-generation failure. The test instance was stopped normally afterward.

A follow-up drag regression used the rebuilt app with the same ten-minute fixture. Dragging the progress thumb from the start to 07:20 and then back to 02:51 placed it at both requested positions while playback remained `PLAYING`. Playback ticks continued updating the elapsed display without pulling the thumb away during either gesture.

The FLAC metadata fallback was checked in the packaged app with a locally supplied tagged file. Re-importing it displayed `Patient Zero — Taylor Swift` in the playlist and `Taylor Swift — Patient Zero` in the player instead of its filename; playback reported FLAC at 48 kHz stereo and stopped normally.

## Not run

macOS 14 codec behavior, a complete VoiceOver audit, multi-display/Spaces behavior, removable-volume reauthorization, physical device disconnect/sleep-wake, long-run CPU/memory, five-participant usability, final App Store identity/signing/provisioning/upload, and optional direct-download Developer ID signing/notarization require environments, hardware, participants, credentials, or product decisions not available in this run.
