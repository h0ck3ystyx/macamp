# ChuckAmp requirement ledger

Statuses: `planned`, `in progress`, `pass`, `fail`, `blocked`, `not run`. Evidence must name an automated result or a dated manual report. Prototype completion does not automatically pass MVP rows.

| ID | Requirement | Owner | Prototype gate | MVP gate | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| FOUND-01 | Reproducible unsigned build, tests, app bundle | T0/T10 | yes | yes | pass | 2026-09-25: debug/release builds, 3 tests, ad-hoc signed `build/ChuckAmp.app`; launch visually verified |
| FOUND-02 | Shared contracts and concurrency/ownership rules | T0 | yes | yes | pass | 2026-09-25: Swift 6 contracts compiled; `docs/CONTRACTS.md` records ownership and invariants |
| AUD-01 | Transport and required codec/container matrix | T1/T4/T8 | subset | full | pass | Prototype WAV/FLAC/AAC/MP3 fixtures; app WAV smoke; full matrix remains T8 |
| AUD-02 | Gapless supported album playback | T1/T4/T8 | lossless + MP3 proof | full fixtures | pass | WAV and tagged MP3 pairs rendered exact 88,200-frame timeline with no silent boundary |
| AUD-03 | Bounded decoding and responsive long-file seek | T4/T8 | yes | yes | pass | Six 4,096-frame buffers/track; 10-minute VBR seek probe passed |
| AUD-04 | Audible 10-band EQ, preamp, bypass, reset, presets | T4/T8 | except presets | full | pass | Graph implementation +11.990 dB probe; presets remain MVP |
| AUD-05 | Overload guidance, indication, output protection | T8 | no | yes | planned | — |
| AUD-06 | Output loss, disconnect, sleep/wake safety | T4/T8 | basic | full | pass | Conservative pause/no-auto-resume implemented; physical device matrix remains MVP |
| AUD-07 | Malformed-file isolation and bounded queue failure | T4/T8 | yes | yes | pass | Coordinator tests bound failures to one traversal |
| LIST-01 | Duplicate-safe add/reorder/remove/select | T2/T5 | yes | yes | pass | Production queue and UI tests |
| LIST-02 | M3U/M3U8 import/export and PLS import | T9 | no | yes | planned | — |
| LIST-03 | Queue and named playlists stay distinct | T9 | no | yes | planned | — |
| LIST-04 | Atomic state persistence and recovery | T2/T7/T9 | core | full | pass | Atomic primary/backup tests; packaged app persists session paused |
| LIST-05 | Persistent authorized access and reauthorization | T2/T9 | core | full | pass | Bookmark lease/stale-access tests; real NSOpenPanel app smoke |
| LIST-06 | Responsive 10,000-entry playlist | T5/T9 | no | yes | planned | — |
| UI-01 | Player, EQ, playlist modules and compact mode | T3/T5 | yes | yes | pass | Packaged app visually verified in all four surfaces |
| UI-02 | Snapping, grouping, detach, hide/close, reset layout | T3/T5 | yes | full displays/Spaces | pass | Geometry/tests and app menu; full display/Spaces matrix remains MVP |
| UI-03 | Open/add/drop/folder ordering and feedback | T2/T5 | yes | yes | pass | NSOpenPanel WAV smoke plus importer/UI tests |
| UI-04 | Shuffle/repeat/previous/removal/filter semantics | T2/T5/T9 | core except filter/Undo | full | pass | Deterministic queue and UI tests; named-list work remains MVP |
| SKIN-01 | Public schema; import/preview/apply/export/remove | T6 | bundled apply | full | pass | Graphite/Paper resolve via schema; external package workflow remains MVP |
| SKIN-02 | Live skin changes preserve playback | T6/T7 | yes | yes | pass | Live selection tests and packaged-app skin switching |
| SKIN-03 | Documented creator starter workflow | T6 | no | yes | planned | — |
| SKIN-04 | Reject unsafe/invalid packages | T6 | no | yes | planned | — |
| SKIN-05 | Enforce resource and decoded-image budgets | T6 | no | yes | planned | — |
| SKIN-06 | Skin failure recovery/default reset | T6 | basic | full | pass | Validate-before-apply retains active skin; native fallback present |
| SKIN-07 | Skin-independent accessibility overrides | T5/T6/T11 | basic | full | pass | Semantic control tests; high-contrast override remains MVP |
| MAC-01 | Native menus, panels, Finder, Dock, drag/drop | T5/T7/T9 | core | full | pass | Native menus/panel/Dock reopen/drop wiring; Finder document types remain MVP |
| MAC-02 | Media commands and Now Playing use shared state | T9 | no | yes | planned | — |
| A11Y-01 | Keyboard and VoiceOver operation | T3/T5/T11 | basic | full | pass | AX tree/control labels and focus visually inspected; full audit remains MVP |
| A11Y-02 | Contrast, focus, non-color states, Reduce Motion | T5/T6/T11 | basic | full | pass | Default skins/non-color queue states verified; full audit remains MVP |
| PERF-01 | Startup, latency, UI, CPU, memory budgets | T11 | smoke | measured | planned | — |
| REL-01 | Long-run and recovery matrix | T11 | smoke | measured | planned | — |
| PRIV-01 | Offline local playback; no telemetry by default | T7/T11 | yes | yes | pass | No network/telemetry dependencies; local fixture app smoke |
| DIST-01 | Dependency provenance and clean install | T10/T11 | development app | release candidate | pass | Ad-hoc signed `build/ChuckAmp.app`; notarized release remains MVP |
