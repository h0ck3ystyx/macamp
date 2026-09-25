# ChuckAmp — agent build plan

September 25, 2026 · Implementation handoff · Prototype implemented; see `docs/PROTOTYPE-REPORT.md`

Product authority: [PRODUCT-DESIGN.md](PRODUCT-DESIGN.md). Read that document before implementing a task. This plan turns its requirements into bounded work; it does not replace its interaction rules or reduce its public-release scope.

## 1. Deliver two clearly named builds

**Prototype:** an installable local Mac app demonstrating real playback, three modular windows, working EQ, and live skin changes. It proves the architecture and visual direction. It is not the public MVP.

**MVP:** all P0 requirements in the product document, including the complete format matrix, external skin import/export, persistence, accessibility, recovery, and release validation.

| Capability | Prototype gate | MVP gate |
| --- | --- | --- |
| Audio | MP3, AAC-LC/M4A, FLAC, WAV; working transport and seek | Entire product format matrix; decoder edge cases |
| Transitions | Captured-output proof for a lossless pair and a tagged MP3 pair | Full supported gapless fixture coverage and documented limitations |
| Windows | Player, playlist, EQ; snapping, detach, compact mode, reset | All scales, multiple displays, Spaces, restoration, close/hide behavior |
| Playlist | Open/add/drop, reorder/remove, shuffle/repeat | Search, Undo, saved lists, M3U/M3U8/PLS, 10,000 entries |
| EQ | Audible 10-band EQ, bypass, preamp, reset | Presets, smoothing, clipping/protection validation |
| Skins | Graphite and Paper through the same schema; live switching | Three skins; customization; safe external packages; creator starter |
| Mac | Native menus, file access, keyboard controls, basic VoiceOver | Media commands, Now Playing, full accessibility/recovery matrix |
| Persistence | Queue, position, skin; relaunch paused | All product state; atomic writes; stale access and migration handling |
| Delivery | Runnable development `.app`, build instructions, demo evidence | Release build, quality evidence, signed/notarized artifact when credentials available |

No fake spectrum, cosmetic EQ, timer-based pretend playback, or hardcoded demo queue qualifies. Hide unfinished optional controls rather than present them as working. Keep the original retro-inspired appearance central to the prototype.

## 2. Team and execution order

Use **one coordinator/integrator and up to three implementation agents at a time**. Roles below can be reused across waves. Do not assign the entire app independently to multiple agents.

| Wave | Coordinator | Worker A | Worker B | Worker C | Gate |
| --- | --- | --- | --- | --- | --- |
| 0 | T0 foundation/contracts | — | — | — | Reproducible build and agreed interfaces |
| 1 | Review contracts and integrate spikes | T1 audio feasibility | T2 queue/files | T3 windows/design feasibility | Architecture proven; dependencies selected |
| 2 | T7 assembly, incremental integration | T4 audio implementation | T5 product UI | T6 skin system | Prototype demo and test report |
| 3 | T10 release preparation | T8 audio completion | T9 data/Mac completion | T6 remaining MVP skin work | P0 feature complete |
| 4 | Integrate fixes and verify release | T11 audio/recovery QA | T11 accessibility/window QA | T11 skin/package QA | MVP release gate |

Dependencies: T0 → T1/T2/T3. T1 → T4 → T8. T2/T3 → T5. T0’s skin contract → T6. T4/T5/T6 → T7 prototype gate. T7 → T9. T8/T9/T6 → final T10/T11 gate. T7 integration starts before its final gate; T10 packaging preparation can proceed while features finish.

Start with the simplest working vertical slice: Open File → authorized URL → decoder → output → state snapshot → player controls. Integrate at least once per completed task; do not wait for three isolated feature branches to be “finished.”

## 3. Foundation and file ownership

Proposed repository layout, created by T0:

```text
ChuckAmp.xcodeproj/             # app target, shared scheme; coordinator owns
ChuckAmp/App/                  # composition root, lifecycle, menus; coordinator
ChuckAmp/Resources/            # asset registration; coordinator
Packages/ChuckAmpKit/
  Package.swift                # coordinator owns dependencies/target graph
  Sources/Contracts/           # coordinator owns shared types/protocols
  Sources/Audio/               # audio agent
  Sources/Library/             # queue/file/persistence agent
  Sources/Skins/               # skin agent
  Sources/PlayerUI/            # UI agent
  Sources/MacIntegration/      # Mac integration agent
  Tests/                       # mirrored ownership by feature
Skins/                        # skin agent: original bundled assets/starter
Tests/Fixtures/               # fixture owner assigned per task
scripts/                      # coordinator: build/test/package entry points
docs/                         # contracts, decisions, evidence, test reports
```

This is a target layout, not a statement that these files exist. The coordinator may simplify target structure during T0 while retaining ownership boundaries. Only the coordinator changes the Xcode project, package manifest, entitlements, shared contracts, or dependency lockfiles. Workers submit requested changes explicitly.

Prefer isolated branches/worktrees when available. In a shared checkout, enforce the listed file ownership and never reset, clean, or overwrite another agent’s work. T5 owns rendering and controls; T6 owns theme data/assets/validation. T6 does not edit views to special-case its skins.

## 4. Contracts to freeze before parallel implementation

T0 writes `docs/CONTRACTS.md` and compiling Swift definitions. These are conceptual contracts; choose exact signatures with the selected compiler and concurrency checks. Workers request changes instead of creating parallel definitions.

| Contract | Required meaning |
| --- | --- |
| `TrackReference` | Stable source identity, access reference, metadata state; no assumption that a path grants permission |
| `QueueEntry` | Unique entry ID + track ID; duplicate source files can occur more than once |
| `PlaybackSnapshot` | Revision, idle/loading/playing/paused/stopped/failed state, entry ID, position, optional duration, volume, EQ, error |
| `PlayerCommand` | Play/pause/stop/seek, previous/next, open/append, select/remove/reorder, shuffle/repeat; one route for UI/menu/media commands |
| `QueueStore` | Owns visible order, actual playback history, traversal policy, and selection; returns stable entry IDs |
| `PlaybackCoordinator` | Sole owner of transport decisions; serializes commands and queue/engine events |
| `AudioEngineClient` | Prepare/current/next scheduling, transport, gain/EQ, typed events with playback generation IDs |
| `Decoder` | Inspect, seek, bounded PCM reads, end-of-stream; describes format, frame counts, delay/padding when known |
| `FileAccessService` | Resolves bookmarks; balanced acquire/release access leases held through decoding; reauthorization result |
| `SessionStore` | Versioned atomic read/write; restores paused; explicit schema migration/failure behavior |
| `SkinManifest` / `ResolvedSkin` | Versioned data schema and validated local assets; canonical control/style keys; no behavior code |
| `WindowLayout` | Module IDs, frames, scale, compact/visible/group state; recoverable when displays change |

Concurrency rules: observable presentation state is main-actor owned; playback coordination is serialized outside the audio render callback; decoding/file work is off the UI thread. UI issues commands, not direct engine calls. Engine events from superseded seeks/loads are discarded using generation IDs. Prefetch cancellation releases its file lease and buffers. Missing duration is distinct from zero.

Specify who selects and commits the next queue item: QueueStore proposes traversal; PlaybackCoordinator stages it with the engine and commits advancement on the matching transition event. Reordering/removing entries invalidates stale prefetch without restarting the current track. This must work with gapless scheduling, repeat, and shuffle.

## 5. Agent task packets

Each task ends with changed files, exact validation commands/results, known limitations, and integration notes. A checklist tick without evidence is not completion.

### T0 — Scaffold and contracts · Coordinator · first

**Assignment:** inspect the Mac/Xcode toolchain and repository instructions; create a Swift macOS 14+ Apple-silicon app, shared build scheme, testable core, and ownership structure. Choose and document the language/concurrency mode. Implement shared contracts and deterministic fake services used only in tests/previews. Create build/test scripts that work without personal signing credentials. Write a contract decision log and requirement-to-task matrix.

**Deliver:** app launches with an empty-state window; unit test runner works; README has exact commands; contracts compile; requirements ledger lists every P0 behavior, task owner, and evidence field. No third-party codec/archive dependency until its owning spike requests one.

**Gate:** a fresh checkout builds using documented commands with no untracked local prerequisites. Required external SDK/toolchain gaps are recorded, not silently bypassed.

### T1 — Prove audio feasibility · Audio agent · after T0

**Assignment:** implement a small executable/test harness to inspect, decode, seek, and play the product’s codec/container fixtures. Prove scheduling across two tracks and inspect trimming metadata. Evaluate native decoding first and identify narrow fallbacks for actual gaps. Probe EQ and output reconfiguration. Keep findings separate from production claims.

**Deliver:** `docs/AUDIO-FEASIBILITY.md`; machine-readable format results including OS/toolchain; generated or redistributable fixtures with provenance; decoder/graph decision and dependency requests. Demonstrate sample-boundary analysis for lossless and tagged MP3 pairs. Unsupported combinations remain failed/blocked in the matrix.

**Gate:** prototype formats and a viable gapless strategy work; remaining MVP formats have a concrete adapter plan. If the approach fails, fix the architecture before UI integration depends on it.

### T2 — Queue, file access, and restoration · Data agent · after T0

**Assignment:** implement QueueStore, file/folder import, asynchronous metadata, bookmark access leases, and versioned session persistence. Follow the product’s open/drop/order/remove/shuffle/repeat rules. Separate selected entry from playing entry and file identity from queue identity. Provide Undo-capable queue mutations for later UI integration.

**Tests:** duplicate entries; removal during playback; shuffle history; manual Next under Repeat One; malformed/missing files; natural folder ordering; stale access; interrupted persistence; restoring paused. Use deterministic seeds for shuffle tests.

**Gate:** fake-engine integration can traverse and mutate a queue deterministically; real files reopen after relaunch with appropriate authorization. No source files are changed or deleted.

### T3 — Window and design feasibility · UI agent · after T0

**Assignment:** build an AppKit prototype of the three windows and compact mode with placeholder state. Demonstrate snapping, connected-group movement, secondary-window detachment, focus, keyboard access, hide/close, and reset. Produce actual-size Graphite and Paper design previews with the product dimensions. Ensure 360 × 160 pt is usable; document any proposed adjustment rather than compressing text blindly.

**Deliver:** runnable window spike, screenshots of stacked/detached/compact states, `docs/WINDOW-DECISIONS.md`, and final rendering/style-key requests for T6.

**Gate:** no inaccessible/offscreen-only recovery path; primary controls remain usable at default scale; window behavior is feasible before visual polish. Placeholder state is confined to this spike/previews.

### T4 — Production audio path · Audio agent · after T1

**Assignment:** implement the real bounded decode/scheduling pipeline behind the agreed interfaces. Wire transport, seeking, prefetch/cancellation, volume, 10-band EQ/preamp/bypass/reset, and typed errors. Supply state/position from the audio path, not a UI timer pretending to be a playback clock. Implement safe output-loss/sleep behavior and generation-based cancellation.

**Tests:** rapid play/seek/next sequences; stale callbacks; queue changes during prefetch; long VBR files; stop/reset; EQ audibility/response; corrupt-file skip bounded to one exhausted traversal.

**Gate:** prototype formats and gapless pair tests pass; no main-thread decoding; repeated seek/skin/window activity does not interrupt output. Report unimplemented MVP format paths precisely.

### T5 — Functional modular UI · UI agent · after T2/T3

**Assignment:** turn the window spike into the actual player, virtualized playlist, EQ, and skin-selection surfaces. Consume snapshots and dispatch shared commands. Implement open/drop feedback, selection vs. playing states, transport, volume, scrubber, shuffle/repeat, EQ sliders, compact mode, module visibility, and Reset Layout. Build native menus and accessible controls with the coordinator’s app wiring.

**Deliver:** Graphite presentation using ResolvedSkin, all required loading/empty/error/paused states, keyboard flow, accessible names/values/focus, and screenshots at default/large scale. Coordinate with T6 through tokens/assets, not cross-owned edits.

**Gate:** real audio/queue integration works end-to-end; no decorative controls masquerade as working features. Spectrum, if present, derives from audio analysis and respects Reduce Motion.

### T6 — Skin engine and authoring · Skin agent · after T0, coordinate T3

**Prototype assignment:** implement manifest v1, asset resolution, state artwork, color/font roles, and live application. Provide Graphite and Paper through the same schema. Prove artwork customization as well as colors. Deliver schema docs and example data early so T5 is not blocked.

**MVP assignment:** add Terminal, accent variations, import/preview/export/remove, creator starter, package validation, bounded extraction/image decoding, and default recovery. Choose an archive dependency through the coordinator; no ad hoc shell extraction of untrusted packages. Validate canonical paths, symlinks, duplicate entries, file count, expanded bytes, dimensions, and aggregate decoded memory. A 64 MiB decoded-asset cap is the starting engineering budget; test it against bundled skins.

**Tests:** malformed/version-mismatched manifests; corrupt/oversized images; traversal and symlink archives; excessive expansion; missing optional assets; export/import round trip. Failed validation leaves the active skin unchanged.

**Gate:** swapping skins during real playback preserves audio state; all bundled skins use the public schema; a person can edit the starter and import it without compiling the app.

### T7 — Assemble and accept the prototype · Coordinator · after T4/T5/T6 prototype portions

**Assignment:** compose one real set of services; route Finder/menu/UI actions consistently; eliminate preview implementations from production. Integrate queue, bookmarks, persistence, playback, theme state, and windows. Resolve API changes centrally. Package a development `.app`.

**Demo script:** launch → open a mixed-format folder → play/pause/seek/next → reorder and remove entries → change EQ and bypass → detach/snap EQ → collapse/expand → switch Graphite/Paper while playing → quit/relaunch paused → reset layout.

**Gate:** every prototype-column item in section 1 passes. Deliver the app path, build instructions, screenshots, automated results, audio-boundary evidence, and a short remaining-MVP checklist. A successful prototype does not close the P0 ledger.

### T8 — Complete audio P0 · Audio agent · after T7, or earlier where independent

**Assignment:** finish every codec/container fixture including HE-AAC/ADTS, ALAC, Vorbis, and Opus. Implement needed fallbacks, trimming, channel rejection, metadata details, chained-stream policy, EQ presets/smoothing, and documented output protection. Test mixed rates and long files. Preserve source silence and never claim bit-perfect playback.

**Gate:** AUD-01 through AUD-07 pass with actual results. Boundary tests measure inserted/dropped frames and continuity against suitable decoded references; do not require lossy samples to equal the original uncompressed waveform. Document precisely where missing padding metadata or rate changes limit guarantees.

### T9 — Complete data and Mac P0 · Data/Mac agent · after T7

**Assignment:** finish saved playlists, M3U/M3U8 import/export, PLS import, relative paths and unsupported URL reporting; add search/reveal/Undo; complete restoration for EQ/window/volume state; implement locate/reauthorize. Connect media commands and Now Playing to the shared coordinator, not a second player. UI changes are handed to the UI owner or ownership is explicitly transferred before editing.

**Gate:** LIST-01 through LIST-06 and Mac interaction rules pass; 10,000-row import remains responsive; no duplicate remote-command handlers; metadata/state remains accurate in the background. Validate sandboxed playlist permissions, removable volumes, and relaunch on actual macOS.

### T10 — Build and distribution · Coordinator · preparation after T0, final after feature completion

**Assignment:** maintain reproducible build/test/package scripts and dependency provenance. Configure bundle identity/document types/entitlements; include all native decoder libraries and skin resources in the app. Produce a release-mode build, release notes, support limitations, licenses, and clean-install instructions. Configure signing/notarization only using available authorized credentials; never print secrets.

**Gate:** clean installation opens audio and skins correctly and passes an offline smoke test. Without signing credentials, deliver the locally runnable artifact and exact signing steps; mark public distribution blocked. Never call an unsigned local build release-ready. Publishing or uploading is a separate action, not part of this plan’s default execution.

### T11 — Independent validation and regression fixes · QA assignments by feature

**Assignment:** audit behavior against the P0 ledger and run the product quality matrix. Review code outside the reviewer’s main implementation area where practical. Add regression tests for discovered behavior bugs; avoid tests that only restate implementation details. Measure startup, playback latency, memory, CPU, and long-run reliability using the product’s measurement conditions.

**Deliver:** `docs/TEST-REPORT.md` with artifact/commit, machine, OS, exact commands, pass/fail/not-run rows, screenshots, measurements, and reproducible defects. Separate automated test evidence from manual observations. Cross-OS, VoiceOver, multi-monitor, signing, and five-participant usability tests require actual access/participants; mark unavailable checks not run.

**Gate:** all P0 criteria pass, or unresolved external blockers are explicitly listed and the build remains a candidate. An agent cannot waive a product requirement merely to report completion.

## 6. Evidence and stop conditions

Automate tests for queue state transitions, scheduling/cancellation, actual decoder fixtures, persistence recovery, playlist parsing, and skin package validation. Use UI/manual checks for focus, window grouping, visual quality, VoiceOver, media-key contention, and device changes. Both types are necessary; screenshots cannot prove playback and unit tests cannot prove usable windows.

Use generated audio or files with redistribution permission. Keep a fixture manifest with codec/container, parameters, expected duration/frames/trimming, provenance, and expected outcome. Do not add a personal music collection to the repository. Capture output in the test graph when possible, then separately verify the hardware-output path.

Stop dependent work and report a concrete blocker when a necessary toolchain/API cannot run, a required format has no viable decoder, or a shared contract cannot support the behavior. Continue independent tasks. Routine design/implementation choices use the defaults above; do not ask the user to resolve every class name or dependency detail.

## 7. Copy/paste kickoff prompts

### Coordinator prompt

```text
Build ChuckAmp according to PRODUCT-DESIGN.md and BUILD-PLAN.md in this repository.
Start with T0, then execute the waves through the prototype gate T7. You may delegate
bounded tasks to up to three concurrent worker agents, retaining one coordinator.
Enforce file ownership and shared contracts. Inspect repository instructions and the
actual toolchain first. Use native Swift/AppKit with the documented defaults.

Implement and validate a real runnable app; do not stop at scaffolding or mockups.
Do not implement deferred features or silently reduce the prototype gate. Integrate
each task as it completes. Record actual commands/results and unresolved blockers.
Deliver the development .app, exact build/run instructions, screenshots, audio test
evidence, and a requirement ledger showing remaining MVP work. Do not publish.
```

### Worker prompt template

```text
Implement task [T-ID] from BUILD-PLAN.md. Read PRODUCT-DESIGN.md and the frozen
contracts first. Own only [ASSIGNED PATHS]. Other agents are working concurrently;
do not reset or rewrite their work. Ask the coordinator for shared contract,
dependency, project-file, or cross-owned UI changes rather than editing those files.

Deliver working code and the task's acceptance evidence. Follow existing behavior
rules and report concrete blockers promptly. At completion list changed files,
tests/commands with results, known limitations, and integration instructions.
Do not claim unrun tests passed. Do not publish or upload artifacts.
```

### MVP continuation prompt

```text
Continue ChuckAmp from the accepted prototype to the full MVP using BUILD-PLAN.md
waves 3–4 and every P0 requirement in PRODUCT-DESIGN.md. Inspect the current evidence
and requirement ledger before assigning work. You may delegate up to three bounded
worker tasks concurrently. Complete T8, T9, remaining T6 work, T10, and T11; preserve
the established file ownership and integrate fixes centrally.

Do not treat prototype exclusions as MVP exclusions. Deliver the app and reproducible
validation report, or identify precisely which release gates remain blocked by real
external prerequisites. Do not fabricate manual/cross-OS/usability results or publish.
```
