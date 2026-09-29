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
| DIST-01 | App Store archive, signing, provisioning, and delivery validation | AS-A/AS-F | development app | App Store processed build | in progress | 2026-09-29: native Xcode target and shared `MacAmp-AppStore` scheme produced a validated unsigned universal arm64/x86_64 archive; distribution identity/profile and App Store Connect processing remain |
| DIST-02 | App Sandbox and persistent authorized file access | AS-A/AS-B | bookmark behavior | sandboxed workflow matrix | in progress | 2026-09-29: ad-hoc package carries App Sandbox, user-selected read/write, and app-scoped bookmark entitlements; it restored and played a saved FLAC without re-selection. Automated tests prove denied scope requests require reauthorization and acquired security scope is released exactly once. Export, live stale access, and `/Volumes/Music/lidarr` disconnect/reconnect matrix remain |
| DIST-03 | Store identity, assets, privacy, compliance, and metadata | AS-C/AS-E | internal identity | App Review complete | in progress | 2026-09-29: Music category, export declaration, skin UTI, privacy manifest, and third-party notices are packaged; icon, final bundle ID/version, privacy report/policy, metadata, screenshots, age rating, rights, territories, and account compliance remain |
| VIS-01 | Rendered-audio visualization independent of codec | VIZ-1 | real tap | full matrix | in progress | 2026-09-29: fixed-capacity atomic bridge captures the shared post-limiter/pre-volume render path; live restored FLAC drove mini and large views; codec matrix remains |
| VIS-02 | Spectrum/scope with measurable EQ response | VIZ-1/VIZ-3 | deterministic DSP | integrated UI | in progress | 2,048-point analysis and bridge tests pass for silence, 1 kHz tone, antiphase stereo, and −6 dB; live spectrum passed; live EQ sweep remains |
| VIS-03 | Mini modes and skin colors | VIZ-3 | mini surface | all skins | in progress | Spectrum/scope/off are wired over the existing player display without changing controls; Studio Graphite live check passed, remaining skins pending |
| VIS-04 | Detachable/fullscreen visualization module | VIZ-3 | windowed | full lifecycle | pass | 2026-09-29: resizable/restorable 640×400 Metal window, native fullscreen/Escape, close/reopen, generic snap/reset layout, and accessible controls verified |
| VIS-05 | Six distinct original presets | VIZ-2/VIZ-4 | bars/scope/phosphor | all six | pass | Metal render paths implement bars, stereo scope, orbit, phosphor trails, tunnel, and aurora; catalog test and live bars/aurora/fullscreen checks pass |
| VIS-06 | Browser, favorite, history, shuffle, lock, cycle | VIZ-4 | state model | UI + persistence | in progress | Preset popup, All/Favorites filter, actual previous history, favorite, lock, and playback-timed cycling are wired; shuffle remains deferred |
| VIS-07 | Bounded smooth transitions | VIZ-4 | two effects max | measured | in progress | Crossfade renders only prior/current geometry and coalesces through latest-value features; live bars-to-Aurora transition passed, cost gate remains |
| VIS-08 | Playback-aware visualization lifecycle | VIZ-1/VIZ-3 | epoch reset | full lifecycle | pass | Prepare/seek/stop/output reset epochs; pause freezes, stop clears, and all-hidden/compact mode stops analysis without touching audio |
| VIS-09 | Persist visualization customization | VIZ-0/VIZ-5 | schema migration | restart proof | pass | Schema-3 migration tests plus live UI paths persist preset, favorite/filter, lock/cycle, sensitivity, mini mode, and visualization window geometry |
| VIS-10 | Safe preset customization | VIZ-4 | schema validator | import/export | planned | Bounded preset file implementation not started |
| VIS-11 | Accessible controls and reduced motion | VIZ-3/VIZ-5 | keyboard/AX | manual audit | in progress | AX labels/focus cover all visible controls; Reduce Motion freezes surfaces, disables cycling/crossfade, and offers an explicit session-only Start action; spoken VoiceOver audit remains |
| VIS-12 | Bounded cost and failure recovery | VIZ-1/VIZ-2/VIZ-5 | counters/fallback | measured gates | in progress | Callback uses fixed copies/atomics and drops on overflow; 2026-09-29 live 30 Hz window sample was 14.3% CPU/112 MiB RSS total app, falling to 3.8% CPU with mini off/window hidden; missing Metal device/pipeline now shows a nonfatal accessible fallback and 106 tests pass; long-run p95 remains |
| VIS-13 | Preserve current app behavior | VIZ-5 | regression suite | release matrix | pass | 2026-09-29: 105 package tests pass, release app packages/signs, and live FLAC playback continued through windowed/fullscreen preset changes |
