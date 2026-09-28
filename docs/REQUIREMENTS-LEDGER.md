# MacAmp requirement ledger

Statuses: `planned`, `in progress`, `pass`, `fail`, `blocked`, `not run`. Evidence must name an automated result or a dated manual report. Prototype completion does not automatically pass MVP rows.

| ID | Requirement | Owner | Prototype gate | MVP gate | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| FOUND-01 | Reproducible unsigned build, tests, app bundle | T0/T10 | yes | yes | pass | 2026-09-26: debug/release builds, 86 tests, ad-hoc signed `build/MacAmp.app`; signature/plist verified |
| FOUND-02 | Shared contracts and concurrency/ownership rules | T0 | yes | yes | pass | 2026-09-25: Swift 6 contracts compiled; `docs/CONTRACTS.md` records ownership and invariants |
| AUD-01 | Transport and required codec/container matrix | T1/T4/T8 | subset | full | pass | Serial bounded decode passed PCM/AIFF, software FLAC/MP3, ALAC, AAC-LC, HE-AAC M4A/ADTS, Vorbis, and Opus on macOS 26; a 300-file network sample included 44.1/96/192 kHz FLAC and ID3-tagged MP3 |
| AUD-02 | Gapless supported album playback | T1/T4/T8 | lossless + MP3 proof | full fixtures | pass | Clean matched-rate FLAC/ALAC/AAC-LC/HE-AAC/MP3/Opus fixture boundaries; ADTS/Vorbis/mixed-rate and approximate legacy-MP3 timing limits documented |
| AUD-03 | Bounded decoding and responsive long-file seek | T4/T8 | yes | yes | pass | Six 4,096-frame buffers/track; two-hour VBR seek to 7,199.25 seconds passed |
| AUD-04 | Audible 10-band EQ, preamp, bypass, reset, presets | T4/T8 | except presets | full | pass | Ten-band graph, smoothing, and six preset tests pass; preset menu exposed |
| AUD-05 | Overload guidance, indication, output protection | T8 | no | yes | pass | LIMIT/SAFE UI plus limiter probe: predicted 3.583 peak, protected 0.733 |
| AUD-06 | Output loss, disconnect, sleep/wake safety | T4/T8 | basic | full | pass | Conservative pause/no-auto-resume implemented; physical device matrix remains MVP |
| AUD-07 | Malformed-file isolation and bounded queue failure | T4/T8 | yes | yes | pass | Coordinator tests bound failures to one traversal |
| LIST-01 | Duplicate-safe add/reorder/remove/select | T2/T5 | yes | yes | pass | Production queue and UI tests |
| LIST-02 | M3U/M3U8 import/export and PLS import | T9 | no | yes | pass | 22 Library tests cover ordering, relative paths, encoding, remote/missing reporting, and export round trips |
| LIST-03 | Queue and named playlists stay distinct | T9 | no | yes | pass | Atomic named-playlist catalog and UI menu; independence/Undo persistence test passes |
| LIST-04 | Atomic state persistence and recovery | T2/T7/T9 | core | full | pass | Atomic primary/backup tests; packaged app persists session paused |
| LIST-05 | Persistent authorized access and reauthorization | T2/T9 | core | full | pass | Bookmark lease/stale-access tests plus restored playback smoke with bookmarks invalidated by an ad-hoc rebuild |
| LIST-06 | Responsive 10,000-entry playlist | T5/T9 | no | yes | pass | Debug measurement: parse 0.159 s plus actor append/search 0.037 s |
| UI-01 | Player, EQ, playlist modules and compact mode | T3/T5 | yes | yes | pass | Packaged app visually verified in all four surfaces |
| UI-02 | Snapping, grouping, detach, hide/close, reset layout | T3/T5 | yes | full displays/Spaces | pass | Geometry tests and live 3-skin × 3-scale matrix; 650 × 520 playlist survives selection/search/compact/relaunch and equalizer close reflows the stack; full display/Spaces matrix remains external |
| UI-03 | Open/add/drop/folder ordering and feedback | T2/T5 | yes | yes | pass | NSOpenPanel WAV smoke plus importer/UI tests |
| UI-04 | Shuffle/repeat/previous/removal/filter semantics | T2/T5/T9 | core except filter/Undo | full | pass | Deterministic queue, filter, Undo, and named-playlist tests pass |
| SKIN-01 | Public schema; import/preview/apply/export/remove | T6 | bundled apply | full | pass | Bundled skins and external `.macampskin` preview/install/export/remove workflow pass package tests |
| SKIN-02 | Live skin changes preserve playback | T6/T7 | yes | yes | pass | Live selection tests and packaged-app skin switching |
| SKIN-03 | Documented creator starter workflow | T6 | no | yes | pass | CreatorExample, schema/package docs, export menu, and round-trip test |
| SKIN-04 | Reject unsafe/invalid packages | T6 | no | yes | pass | Traversal, symlink, duplicate, corrupt image, canonical-name, and schema tests pass |
| SKIN-05 | Enforce resource and decoded-image budgets | T6 | no | yes | pass | 20 MiB archive, 80 MiB expanded, 256-file, 4096 px, 64 MiB decoded limits tested |
| SKIN-06 | Skin failure recovery/default reset | T6 | basic | full | pass | Validate-before-apply retains active skin; native fallback present |
| SKIN-07 | Skin-independent accessibility overrides | T5/T6/T11 | basic | full | pass | Native semantics/focus remain app-owned; Increase Contrast override and bundled-skin contrast regression test pass |
| MAC-01 | Native menus, panels, Finder, Dock, drag/drop | T5/T7/T9 | core | full | pass | Native menus/panel/Dock reopen/drop wiring and Finder document types are packaged |
| MAC-02 | Media commands and Now Playing use shared state | T9 | no | yes | pass | One retained SystemMediaController routes MPRemoteCommandCenter to coordinator and updates Now Playing from shared snapshots |
| A11Y-01 | Keyboard and VoiceOver operation | T3/T5/T11 | basic | full | in progress | Explicit focus loops, state-aware labels/values/actions, Space playback, and AX inspection pass; spoken VoiceOver release audit remains |
| A11Y-02 | Contrast, focus, non-color states, Reduce Motion | T5/T6/T11 | basic | full | pass | Bundled colors enforce 4.5:1; Increase Contrast override, focus rings, non-color queue states, and no-animation Reduce Motion behavior verified |
| PERF-01 | Startup, latency, UI, CPU, memory budgets | T11 | smoke | measured | not run | 10k import measured; startup/CPU/memory/long-run measurements require an unlocked interactive host |
| REL-01 | Long-run and recovery matrix | T11 | smoke | measured | not run | Automated corruption/output-loss paths pass; physical route/sleep and long-run matrix not run |
| PRIV-01 | Offline local playback; no telemetry by default | T7/T11 | yes | yes | pass | No network/telemetry dependencies; local fixture app smoke |
| DIST-01 | Dependency provenance and clean install | T10/T11 | development app | release candidate | blocked | Reproducible ad-hoc signed candidate and ZIPFoundation notice complete; Developer ID signing/notarization credentials unavailable |
| VIS-01 | Rendered-audio visualization independent of codec | VIZ-1 | real tap | full matrix | in progress | Shared PCM/feature contracts and AudioAnalysis target compile; post-limiter tap and bounded callback bridge remain |
| VIS-02 | Spectrum/scope with measurable EQ response | VIZ-1/VIZ-3 | deterministic DSP | integrated UI | in progress | Accelerate 2,048-point analysis tests pass for silence, 1 kHz tone, antiphase stereo, and −6 dB level change; EQ/tap integration remains |
| VIS-03 | Mini modes and skin colors | VIZ-3 | mini surface | all skins | planned | Mini mode contract exists; no visible surface yet |
| VIS-04 | Detachable/fullscreen visualization module | VIZ-3 | windowed | full lifecycle | planned | `PlayerModule.visualization` is schema-backed; window/render lifecycle remains |
| VIS-05 | Six distinct original presets | VIZ-2/VIZ-4 | bars/scope/phosphor | all six | in progress | Six stable built-in IDs/effect identities and catalog test exist; renderers remain |
| VIS-06 | Browser, favorite, history, shuffle, lock, cycle | VIZ-4 | state model | UI + persistence | planned | Settings/command contracts cover favorites, filter, lock, and cycle |
| VIS-07 | Bounded smooth transitions | VIZ-4 | two effects max | measured | planned | Renderer implementation not started |
| VIS-08 | Playback-aware visualization lifecycle | VIZ-1/VIZ-3 | epoch reset | full lifecycle | in progress | Epoch/sequence discontinuity semantics are represented in contracts/analyzer; playback integration remains |
| VIS-09 | Persist visualization customization | VIZ-0/VIZ-5 | schema migration | restart proof | in progress | Session schema 3 round-trip and schema-1 migration tests pass; UI mutation path remains |
| VIS-10 | Safe preset customization | VIZ-4 | schema validator | import/export | planned | Bounded preset file implementation not started |
| VIS-11 | Accessible controls and reduced motion | VIZ-3/VIZ-5 | keyboard/AX | manual audit | planned | Reduced-motion session preference is persisted; UI remains |
| VIS-12 | Bounded cost and failure recovery | VIZ-1/VIZ-2/VIZ-5 | counters/fallback | measured gates | planned | Performance and renderer failure work not started |
| VIS-13 | Preserve current app behavior | VIZ-5 | regression suite | release matrix | in progress | 102 package tests pass after VIZ-0; live audio/render integration has not begun |
