# MacAmp visualization research and requirements

September 28, 2026 · Proposed feature expansion · Research, not implemented functionality

Related: [product definition](../PRODUCT-DESIGN.md), [implementation spec](VISUALIZATION-BUILD-SPEC.md).

The original product document calls the project ChuckAmp; the current package and application use MacAmp. This document follows the implemented name. Advanced visualizations were previously exploratory: the scope below is a proposed visualization release, not a retroactive claim about the existing MVP.

## Recommendation

Build two connected experiences: a lightweight spectrum/oscilloscope in the player, and a detachable visualization window with original, audio-reactive Metal effects. Add preset selection, favorites, automatic transitions, fullscreen, and safe parameter customization.

Investigate existing MilkDrop presets through a separate projectM compatibility spike. Do not make native visualizations depend on that spike, and do not call original Metal effects “MilkDrop compatible.” AVS preset support is a separate, deferred project.

## 1. Research findings

### The small display is its own feature

Winamp documents spectrum, oscilloscope, and off modes, plus analyzer peaks, band width, decay speeds, and several drawing styles. This is the useful everyday experience while the player remains small. **Design implication:** ship a responsive miniature display with clear modes and skin colors, independently of the immersive renderer. [Winamp classic visualization settings](https://support.winamp.com/winamp-desktop-player-for-windows)

### AVS emphasizes constructing effects

Advanced Visualization Studio is an editable preset system. The maintained `vis_avs` port exposes a library, supports legacy binary presets and a newer JSON representation, and incorporates several formerly external effects. Its documentation lists Windows/Linux builds, 64-bit support as future work, and restrictions around external APE effects. It is not an established drop-in Apple-silicon dependency. **Design implication:** borrow the idea of customizable effects, but defer `.avs` import and a full effect editor. [AVS port and current status](https://github.com/grandchild/vis_avs)

### MilkDrop emphasizes evolving imagery

Ryan Geiss describes MilkDrop as audio waveforms rendered through a visual feedback loop. MilkDrop 2 adds programmable pixel shaders. Its controls include preset selection, previous/next, smooth transitions, hard cuts, random/sequential traversal, and locking a preset. **Design implication:** a visualization experience needs browsing and transition behavior, not just one animated canvas. [Original MilkDrop manual](https://www.geisswerks.com/milkdrop/milkdrop.html)

MilkDrop presets combine parameters, initialization/per-frame/per-vertex equations, custom waves/shapes, and shader code. Inputs include audio samples, time, frequency-band measures, and damped band measures. A `.milk` file is therefore more than a palette file. **Design implication:** compatibility requires equation, timing, audio-analysis, and shader semantics; renaming a JSON preset or converting a few colors is insufficient. [Original preset authoring reference](https://www.geisswerks.com/milkdrop/milkdrop_preset_authoring.html)

### Reuse options have different costs

| Option | Verified basis | Product assessment |
| --- | --- | --- |
| Original Metal renderer | Apple's MTKView is a Metal drawing surface | Best default for a native Mac feature; original presets only |
| projectM | Reusable MilkDrop-oriented library; PCM analysis and OpenGL rendering; core identified as LGPL-2.1 | Preferred compatibility experiment; packaging, licensing, OpenGL integration, and preset accuracy need proof |
| Butterchurn | MIT-licensed WebGL 2 implementation; Web Audio input; preset loading and blending | Alternative if a local web renderer is acceptable; requires a native-audio bridge and separate resource measurements |
| AVS port | Legacy preset/effect system with platform/architecture work remaining | High uncertainty for this app; defer |

Sources: [MTKView](https://developer.apple.com/documentation/metalkit/mtkview), [projectM](https://github.com/projectM-visualizer/projectm), [Butterchurn](https://github.com/jberg/butterchurn), [AVS](https://github.com/grandchild/vis_avs).

projectM documents differences in equation parsing and HLSL-to-GLSL translation, including shader features that do not translate correctly. It also documents resolution-dependent rendering differences. Compatibility must be measured against a declared preset corpus, not advertised as universal. [projectM compatibility notes](https://github.com/projectM-visualizer/projectm/wiki/Milkdrop-Compatibility)

Apple identifies OpenGL as deprecated and provides a migration path to Metal. **Inference:** making an OpenGL engine optional limits the cost of future migration; this does not mean projectM cannot run on current Macs. [Apple migration guidance](https://developer.apple.com/documentation/metal/migrating-opengl-code-to-metal)

These sources were consulted September 28, 2026. Historical MilkDrop documents describe original behavior, not current Mac APIs. Repository default branches can change; implementation must pin a tested revision. Engine licenses do not establish permission to redistribute every community preset or texture.

## 2. Scope

| Stage | Required | Explicitly deferred |
| --- | --- | --- |
| V0: technical prototype | Actual PCM analysis, mini spectrum/scope, detached Metal window, one feedback effect, pause/seek/hidden handling | Legacy presets and authoring UI |
| V1: visualization MVP | Six original presets, fullscreen, browser, favorites, lock/cycle, smooth transitions, parameter variants/import/export, accessibility and resource gates | `.milk`/`.avs` compatibility, node editor, arbitrary shaders/scripts |
| V2: compatibility candidate | projectM proof with a pinned corpus and measured results; separately decide whether to ship | Universal compatibility or original Windows DLL loading |

All versions visualize the app's own playback. No microphone, system-audio capture, internet service, recording/exported video, desktop wallpaper mode, or multi-output visualizer is required. One large visualization window plus the miniature display is sufficient.

## 3. User experience

### Mini display

Modes: Spectrum, Oscilloscope, Off. Select them from an accessible menu; double-click opens the larger visualization window. The display uses skin palette tokens with safe defaults for existing skins. Do not shrink current transport targets or track text to insert it; review the player layout at actual size first. Compact mode can omit it.

Spectrum uses 32 bands with optional peak markers. Oscilloscope offers line and filled styles; stereo detail belongs in the larger window. Both are derived from currently rendered audio, including EQ changes. App volume does not change visual intensity; provide a separate visual sensitivity control.

### Visualization window

Default content size 640 × 400 pt; minimum 360 × 240 pt. Open detached; support existing snap/group behavior when windowed. Native fullscreen uses the chosen display; Escape exits fullscreen without stopping playback. Closing hides the visualizer and releases its ongoing work. Reopening restores the selected preset and windowed frame, not automatic fullscreen.

Toolbar: preset name, Previous, Next, Favorite, Lock, Cycle, Fullscreen, Settings. Show controls on pointer movement or keyboard focus; hide after three seconds only if no control has focus and no menu is open. Track-title overlay is optional and off by default.

Keep Space for audio play/pause, even with visualization focus. Menu commands and visible controls provide all preset operations; choose nonconflicting shortcuts during UI integration. Do not reuse MilkDrop's Space-to-next behavior here.

### Preset browsing and playback

Use static thumbnails, names, and author credit; do not run a grid of live previews. Search by name; filter All/Favorites. Previous follows actual visual preset history. Next advances within the selected filter; shuffle uses a nonrepeating bag until exhausted. An empty Favorites filter shows an empty state without replacing the active preset.

Automatic cycling defaults off. When enabled, dwell for 30 seconds, then crossfade for 2 seconds. Offer dwell 10–120 seconds and transition 0–5 seconds. Lock prevents automatic changes; manual selection still works and remains locked. Preset timing pauses with audio and while all visualization surfaces are hidden. Next requests during a transition coalesce to one pending selection.

### Original preset collection

| Preset | Visual behavior | Sound mapping |
| --- | --- | --- |
| Classic Bars | Crisp colored columns and falling peaks | Frequency energy |
| Stereo Scope | Two clean waveform traces | Left/right samples and level |
| Orbit | Luminous circular waveform | Bass expands radius; waveform shapes perimeter |
| Phosphor | Wave traces with decaying trails | Waveform injection into feedback texture |
| Tunnel | Slowly warped geometric tunnel | Bass changes scale; midrange changes rotation |
| Aurora | Soft layered ribbons | Three broad frequency bands change shape and color |

These are proposed original effects, not claims to recreate named Winamp presets. Phosphor, Tunnel, and Aurora provide the evolving imagery that makes this more than an enlarged meter. Keep motion readable and avoid full-screen white flashes in the bundled collection.

## 4. Testable requirements

| ID | V1 requirement | Acceptance evidence |
| --- | --- | --- |
| VIS-01 | Visualize rendered app audio independently of source codec | MP3/FLAC/Opus and both playback lanes feed the same analysis path; no microphone permission |
| VIS-02 | Real spectrum/scope with EQ response | Sine sweep, stereo, silence, and EQ-change fixtures produce expected measured features |
| VIS-03 | Mini modes and skin colors | All current skins and an older package work; Off stops mini drawing |
| VIS-04 | Detachable/fullscreen module | Snap, resize, Escape, close/reopen, display removal, and Reset Layout work without changing audio |
| VIS-05 | Six distinct original presets | Each renders actual PCM and is usable at small/windowed/fullscreen sizes |
| VIS-06 | Browser, favorite, history, shuffle, lock, cycle | Deterministic state tests include zero/one preset and transition-time repeated commands |
| VIS-07 | Smooth transitions | No audio interruption or black intermediate frame; at most two live effect renderers |
| VIS-08 | Playback-aware lifecycle | Pause freezes immediately; stop clears; seek discards stale analysis; hidden surfaces cease rendering |
| VIS-09 | Persist customization | Preset, favorite/filter, parameters, quality, and window frame survive restart; no auto-fullscreen |
| VIS-10 | Safe customization | Allowed numeric/palette parameters round-trip; malformed files rejected without changing active visuals |
| VIS-11 | Accessible controls and reduced motion | Keyboard/VoiceOver operate controls; Reduce Motion disables automatic cycling and continuous animation until explicit per-session override |
| VIS-12 | Bounded cost and failure recovery | Resource budgets pass; a recoverable renderer error shows a static error state while playback continues |
| VIS-13 | Preserve existing app behavior | Gapless, seek, output-change, skin switching, session migration, and current regression suites pass |

In reduced-motion mode show static artwork with the preset name and an explicit Start Animation action. Do not announce frame-by-frame visual changes to VoiceOver. Freeze and hide controls must remain accessible. Do not claim photosensitivity safety certification.

## 5. Completion and product decisions

V0 is complete when the real audio path drives a native canvas without harming playback. V1 is complete only when VIS-01–13 pass; pictures of a visualization are not audio-reactivity evidence. V2 compatibility is separately accepted and cannot be inferred from V1.

Recommended defaults are original Metal effects first, projectM compatibility second, and parameter customization before a programmable editor. If importing a user's existing `.milk` collection becomes a launch requirement, promote V2 explicitly and budget for it rather than treating it as a small import feature.
