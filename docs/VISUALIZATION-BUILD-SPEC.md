# MioAmp visualization build specification

September 28, 2026 · Implementation started · Companion to [requirements and research](VISUALIZATION-REQUIREMENTS.md)

Implementation checkpoint: VIZ-0 contracts and package scaffolding are complete. Session schema 3 supplies backward-compatible visualization defaults, `AudioAnalysis` contains the first deterministic Accelerate analysis core and latest-value mailbox, and `Visualizations` defines the six built-in preset identities. The audio tap, bounded callback bridge, Metal renderer, and visible UI remain subsequent work.

## 1. Current integration points

Inspected source, not a new runtime verification:

- `Package.swift`: Swift tools 6.2, macOS 14, modular Swift package targets.
- `Packages/MioAmpKit/Sources/Audio/ProductionAudioEngine.swift`: `NativeAudioEngineClient`; two player lanes → track mixer → EQ → peak limiter → main mixer/output.
- `Packages/MioAmpKit/Sources/PlayerUI/PlayerViews.swift`: player/compact/EQ/playlist views; no spectrum implementation found in inspected app sources.
- `Packages/MioAmpKit/Sources/PlayerUI/PlayerUIModule.swift`: `PlayerUIWindowController`, snap and scale geometry.
- `Packages/MioAmpKit/Sources/Contracts/PersistenceAndSkins.swift`: four `PlayerModule` cases and session schema 3.
- `MioAmp/App/main.swift`: composition and command routing.

The renderer must extend this architecture, not create another decoder, player, or media-command owner. Read [shared contracts](CONTRACTS.md) and [audio implementation](AUDIO-IMPLEMENTATION.md) before editing. Do not use decoded-ahead buffers as if they were currently audible: the engine can schedule seconds ahead.

## 2. Module boundaries

Add `AudioAnalysis` and `Visualizations` package targets and mirrored tests. Shared value types belong in Contracts. Audio owns tap installation/lifecycle; AudioAnalysis owns the bounded bridge and DSP; Visualizations owns native effects and preset state; PlayerUI owns views/window interaction; App owns composition. No Audio → PlayerUI/Metal dependency.

```text
Audio output graph
  post-limiter / pre-app-volume tap
                ↓ bounded PCM copy
       single-producer/single-consumer bridge
                ↓ analysis worker
       timestamped feature snapshots
           ↙                     ↘
  mini spectrum/scope       Metal effect renderer
                                  ↓
                            window/fullscreen
```

A future compatibility adapter consumes a separate bounded PCM feed supplied by the analysis worker. Let projectM use its own analysis semantics; do not substitute our normalized bands for its expected PCM inputs.

## 3. Audio capture and transport contract

**Proposed tap point:** peak-limiter output, before app volume on the main mixer. This reflects EQ/protection while keeping visual intensity independent of the volume slider. Confirm tap format and timing experimentally; installing a tap must not force a new sample rate or rebuild a playing graph. The API candidate is [AVAudioNode.installTap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)).

| Contract | Fields / semantics |
| --- | --- |
| `VisualizationPCMHeader` | Monotonic sequence, analysis epoch, audio sample time, host time when valid, sample rate, channel count, frame count |
| `VisualizationFeatures` | Sequence/epoch/time, stereo waveform, normalized spectrum, per-channel RMS/peak, bass/mid/treble energy, smoothed energies, onset strength, validity/staleness |
| `VisualizationSettings` | Mini mode, preset ID, user overrides, favorites, cycle/filter/history policy, quality, motion preference |
| `VisualizationCommand` | Show/hide, select/previous/next preset, favorite, lock/cycle, set parameter/quality; separate from audio transport commands |
| `VisualizationRenderer` | Prepare built-in preset, resize, render from features/time, reset epoch, suspend, release; serialized on its render queue |

Do not pass Swift arrays or AsyncStream events from the audio callback. Use preallocated PCM storage, audited atomic index publication, and one worker consumer. Starting capacity: 32 slots × 1,024 stereo Float32 frames, about 256 KiB plus headers. Split larger callbacks into slots; if full, drop incoming visualization data, increment a counter, and never wait. The consumer discards stale queued data and resets overlap state on sequence gaps. No producer overwriting a slot the consumer owns.

The audio callback does no FFT, rendering, file access, actor hop, logging, allocation, or blocking lock. Counters are sampled off-thread. Audit the actual implementation for ARC/allocation effects; labeling a Swift class Sendable does not make callback operations real-time safe.

Install at most one tap at that bus. Enable/disable consumption outside the callback. Keep storage alive through callback teardown; verify whether tap removal is glitch-free. If it is not, leave a cheap inactive tap until the graph next stops. Hidden means no analysis/render work, not necessarily immediate graph mutation.

Increment a separate analysis epoch on seek, stop, graph/output-format reset, and replacement playback. Flush DSP/feedback history on discontinuities; a natural contiguous next-track transition does not need a visual reset. Reject snapshots from old epochs. Rebuild format-dependent buffers off the audio thread before accepting the new format.

## 4. Analysis defaults

Use Accelerate/vDSP for native analysis; see [Apple FFT reference](https://developer.apple.com/documentation/accelerate/fast-fourier-transforms). These numerical defaults are engineering proposals, not emulation of MilkDrop's formulas.

- Worker resamples to 48 kHz when necessary using a stateful anti-aliasing converter; retain stereo. Never change the playback rate for visualization.
- 2,048-sample Hann FFT, 512-sample hop. Roughly 42.7 ms analysis window at 48 kHz. Preserve overlap across callbacks and clear it on sequence gaps.
- Average left/right **spectral power**, not channel samples, so antiphase stereo does not disappear. Preserve separate waveform channels; replicate mono for display.
- Aggregate 32 logarithmic bands from 30 Hz to min(16 kHz, source Nyquist). Document bin weighting, window gain correction, and power normalization. Clamp unusable bands for low-rate sources.
- Map a fixed calibrated power range to display intensity, initially −72 to 0 dBFS. Do not label the mini display as a calibrated audio meter. Silence must not normalize into bright bars.
- Initial display attack 25 ms, release 180 ms; peak hold 250 ms and decay 24 dB/s. Use elapsed-time coefficients so behavior is stable across frame rates.
- Broad bands: bass 30–250 Hz, mid 250–4,000 Hz, treble 4,000–16,000 Hz. Publish raw and 300 ms smoothed power. Clip all derived features to finite documented ranges.
- Onset candidate: positive spectral flux against a rolling adaptive baseline, 120 ms refractory interval, gated below −60 dBFS RMS. Name it onset/beat strength; do not claim BPM or beat-grid accuracy.
- Waveform snapshot: up to 512 points per channel with stable triggering or envelope-aware reduction to avoid unreadable flicker. Do not use arbitrary frame decimation that aliases a high-frequency tone into false low-frequency motion.

Publish at most 60 snapshots/second through a latest-value mailbox; render consumers never accumulate queues. For mini-only mode, permit 30 Hz publication. Use timestamps to discard old data; pause freezes immediately from playback state, even if queued audio analysis remains. Stop clears canvas; silence during playing decays naturally to baseline. Sensitivity alters rendering only, never PCM or audible gain.

## 5. Native rendering

Use MTKView with precompiled bundled Metal shaders, one command queue, and bounded reusable buffers. Confirm SwiftPM resource compilation and app-bundle loading in the first spike. Do not assume Xcode-only shader build steps exist in the current packaging flow.

Implement scope/bars first, then Phosphor. Feedback effects use ping-pong textures: previous image → transformed/decayed image → new audio-driven geometry → output. Never sample and write the same texture in one pass. Separate visualization time from playback position so seeking cannot create giant simulation steps. Clamp resume delta; no hidden-time catch-up loops.

Use frame-rate-independent feedback: derive decay from elapsed seconds, e.g. `decay = exp(-dt / trailLifetime)`. Parameter bindings to bass, mid, treble, onset, and waveform are predefined code paths. No general expression interpreter in V1.

Transition by rendering outgoing/incoming effects separately and blending outputs over the configured interval. At most two effect states; coalesce repeated selections to the most recent pending request. Allocate within the global texture budget; if a transition cannot fit, use a short fade through a held frame rather than exceeding the budget. Shader/device failures fall back to a static error canvas; built-in failures must not restart the audio engine. An in-process native crash is not claimed to be isolated.

Quality profiles, measured in actual render pixels rather than macOS points:

| Profile | Frame cap | Internal long-edge cap |
| --- | --- | --- |
| Low | 30 fps | 960 px |
| Balanced, default | 60 fps | 1,440 px |
| High | 60 fps | 1,920 px |

Preserve aspect ratio and scale to the drawable. Lower internal resolution before reducing frame rate; avoid oscillation with a five-second reassessment interval. Thermal pressure/Low Power Mode selects Low unless explicitly overridden for the session. Suspend occluded/minimized/hidden windows; analysis remains active only if another visible surface needs it.

## 6. Presets, skins, and persistence

V1 `.mioampviz` files are UTF-8 JSON, max 64 KiB, containing schema version, ID/name/author, an allowlisted built-in effect ID, palette, and bounded parameter overrides. They contain no assets, paths, URLs, shader code, script, or executable component. Export creates a variant; it does not export the renderer itself.

Example proposal:

```json
{
  "schemaVersion": 1,
  "id": "local.phosphor-amber",
  "name": "Amber Phosphor",
  "author": "Local user",
  "effect": "phosphor",
  "palette": ["#FFBF47", "#6F420C", "#080A0C"],
  "parameters": {"sensitivity": 1.0, "trailSeconds": 0.8, "motion": 0.35}
}
```

Define per-effect keys/ranges in one schema: sensitivity 0.25–4, trail 0–2 seconds, motion 0–1 as starting ranges. Reject unknown schema/effects/parameters, nonfinite or out-of-range numbers, excessive strings, and duplicate identity collisions unless the user explicitly chooses replacement. Keep the active variant on failure. Preserve built-in IDs; imported files cannot replace bundled implementation code.

Skin controls frame/chrome and mini-display colors; preset controls large-canvas imagery. Changing skin does not change preset or reset its feedback. Existing skin manifests remain valid via fallback tokens. Do not embed visualization scripts in `.chuckskin`/current skin packages.

`PlayerModule.visualization`, backward-compatible settings defaults, and session schema 3 migration are now implemented. Tests load schema-1 and schema-2 historical representations. Persist windowed geometry/settings but not GPU buffers, PCM, or fullscreen activation. Avoid restoring continuous animation against Reduce Motion preferences.

## 7. Budgets and validation

Proposed gates on an M1/8 GB release build, starting with macOS 14 and the newest supported OS. Record measured results; unavailable hardware/OS runs remain not run.

| Area | Gate |
| --- | --- |
| Audio integrity | Existing captured gapless/seek/output probes pass with visuals off/on; zero new app-caused underruns during 60-minute mixed-format stress |
| Reactivity | Analysis-to-presentation timing report; software PCM timestamp to submitted frame p95 ≤100 ms, excluding separately measured device/display latency |
| Mini cost | Incremental CPU ≤3 percentage points of one core; added resident memory ≤20 MiB |
| Large canvas | Balanced 1,440 px profile: p95 CPU submit and GPU execution each ≤16.7 ms over five minutes per effect; record missed presentation frames separately |
| Memory | Added resident memory ≤150 MiB; explicit texture allocation ≤96 MiB including transitions; no growth over 1,000 switches |
| Hidden | No continuous render/FFT activity within 250 ms; bounded inactive capture permitted as documented |
| Failure | Drop visual data under overload; never backpressure audio; bad preset leaves prior selection active |

Tests: deterministic tone/sweep/silence/impulse, antiphase and one-channel audio, mono, 44.1/48/96/192 kHz, rate change, rapid seeks, gaps/drop counters, NaN inputs, decoder-lane transitions, pause/stop, prolonged silence, EQ and volume independence. Tone peak should land in the documented band; −6 dB amplitude change should produce approximately −6 dB in the internal calibrated level within stated tolerance.

Use deterministic seeds and fixed feature sequences for render regression captures. Compare with tolerance and inspect video, not cross-device pixel identity. Verify feedback decay at 30/60 fps, resized textures, scene diversity, fullscreen/display disconnection, reduced motion, VoiceOver, skin changes, and session migration. Run current regression tests; do not rewrite old pass records as if this feature had been tested.

## 8. Bounded agent assignments

Coordinator owns Package.swift, shared contracts, composition, migrations, and integration evidence. Up to three workers can proceed after interfaces freeze. This is a handoff plan; no agents were launched for this research task.

| Task | Ownership | Dependencies | Deliverable / exit gate |
| --- | --- | --- | --- |
| VIZ-0 | Coordinator | None | Contract revision, module scaffolding, requirement ledger, layout/tap decisions |
| VIZ-1 | Audio + AudioAnalysis | VIZ-0 | Real tap/bridge/DSP, discontinuity tests, timing and underrun probes; VIS-01/02 |
| VIZ-2 | Visualizations renderer | VIZ-0; synthetic fixtures initially | Metal resource pipeline, bars/scope/Phosphor, feedback/resize tests |
| VIZ-3 | PlayerUI | VIZ-0 | Mini surface and fourth window, controls/fullscreen/reduced-motion; VIS-03/04/11 |
| VIZ-4 | Renderer + preset owner | VIZ-2 | Remaining effects, browser-state model, bounded transitions, JSON variants; VIS-05/06/07/10 |
| VIZ-5 | Coordinator + QA | VIZ-1–4 | Persistence, real integration, profiling, regressions; VIS-08/09/12/13 |
| VIZ-C | Separate compatibility worker | VIZ-1 and V0 accepted | projectM feasibility report only; no core rewrite |

V0 demo: open real track → spectrum/scope → Phosphor window → change EQ/volume → seek/pause/resume → hide/reopen → confirm playback unaffected. V1 demo adds all six effects, preset browser, favorite/cycle/lock, fullscreen, export/import a variant, skin swap, and relaunch.

## 9. MilkDrop compatibility spike

Pin a projectM revision, build arm64, feed real timestamped PCM from our worker, render in a dedicated OpenGL-backed view, and measure resize/fullscreen/resource behavior. Do not undertake an HLSL-to-Metal port in this spike. Inspect license/dependency/texture provenance and reproducible packaging before recommending adoption.

Use 30 named, legally usable presets covering classic equations, custom waves/shapes, warp/composite shaders, textures, and known unsupported constructs. Record original preset hash, engine revision, load/compile result, visual/reference comparison where available, resource cost, and missing features. Report category-level results rather than only a flattering aggregate pass rate. Modified presets get new identifiers and retain attribution.

A load success is not rendering fidelity. If an original MilkDrop reference cannot be run, say fidelity is unverified. Do not promise `.avs`, MilkDrop 3 extensions, Windows DLLs, or all `.milk` files. Before enabling arbitrary external presets, establish parser/resource limits and a process-isolation design for code-like preset execution; a file-size cap alone does not bound execution or GPU cost.

The decision report compares projectM with a narrowly scoped Butterchurn experiment only if the native integration fails its gates. That alternative must prove offline WebGL, PCM bridging without duplicate audio output, resource cost, navigation/network restrictions, and recovery; an embedded browser is not free compatibility.

## 10. Agent kickoff

```text
Implement V0 from docs/VISUALIZATION-REQUIREMENTS.md and
docs/VISUALIZATION-BUILD-SPEC.md against the existing MioAmp app. Read the current
contracts and audio graph first. Freeze the analysis/render interfaces in VIZ-0,
then implement VIZ-1, VIZ-2's prototype scope, and VIZ-3's prototype scope. You may
delegate bounded tasks to three workers with nonoverlapping ownership.

Use actual post-limiter/pre-volume rendered PCM, not decoded-ahead data or random
animation. Keep the audio callback bounded and free of analysis/rendering work.
Deliver a runnable app, tone/silence/seek tests, playback regression results,
screenshots/video, and measured CPU/memory/timing. Mark unrun checks honestly.
Do not add projectM, arbitrary shaders, or AVS compatibility to this prototype.
```
