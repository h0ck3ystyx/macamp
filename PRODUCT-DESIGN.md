# MioAmp — product design and requirements

Version 0.1 · September 25, 2026 · Draft for product definition

**Proposal:** a small, native Mac audio player with the character of classic Winamp: a compact player, detachable playlist and equalizer, and an interface people can make their own. Open a file, press play, arrange the pieces, pick a skin. Everything essential works offline.

“MioAmp” is a working name drawn from this workspace. This document defines a proposed product, not implemented capabilities. Requirements, dimensions, budgets, and priorities below are recommendations unless explicitly identified as research findings.

## 1. Product intent

Build an everyday player for people who own audio files and enjoy a personal desktop. The product should feel like a small piece of audio equipment: immediate, tactile, dependable, and expressive.

Primary audiences:

- **Everyday listeners:** open downloaded music, albums, mixes, and recordings without importing them into a large library.
- **Local collection owners:** listen to MP3, lossless albums, and newer compressed formats with reliable queues and transitions.
- **Desktop customizers:** change colors and artwork, arrange modules, and create and share skins.

Core jobs: “play this folder,” “keep a small player beside my work,” “listen to an album uninterrupted,” and “make this player look like mine.”

Success means someone can play a file immediately, understand the controls without a tutorial, leave the app running comfortably, and personalize it without programming.

## 2. Research: what to borrow from Winamp

The reference is **classic Winamp’s compact, modular interaction model**, rather than the full scope of its later media suite.

Winamp’s documentation describes a playlist with drag-and-drop loading and saved lists; separate access to an equalizer and other panels; collapsed “Window Shade” mode; and skin preferences for docking, scaling, fonts, and installed skins. It distinguishes Classic `.wsz` and Modern `.wal` skins. These establish modular windows, compact states, and customization as concrete reference behaviors. [Winamp desktop documentation](https://support.winamp.com/winamp-desktop-player-for-windows)

Webamp is a browser reimplementation of Winamp 2 with skin support. Its repository also contains an equalizer-preset parser and a separate prototype for modern skins. It is useful as an interaction and compatibility reference; it does not establish that a native Mac app can inherit its behavior without additional work. [Webamp project](https://github.com/captbaritone/webamp)

The Winamp Skin Museum’s implementation documents skins as ZIP archives and generates consistent screenshots for browsing them. This suggests two valuable ideas for MioAmp: portable skin packages and previews that make a skin understandable before installation. [Skin Museum technical documentation](https://github.com/captbaritone/webamp/blob/master/packages/skin-database/docs/database.md)

| Reference idea | Proposed interpretation for Mac |
| --- | --- |
| Compact transport surface | Playback controls remain visible without opening a library |
| Separate player, playlist, and EQ | Three independently visible modules that snap together |
| Collapsed player | A horizontal strip with track, time, and essential transport |
| Skins as personal expression | Shareable artwork and theme packages, plus simple built-in customization |
| Dense audio information | Time and track first; codec, bitrate, and sample rate secondary |
| Animated spectrum | Small optional spectrum, with reduced-motion and off states |

**Design judgment:** preserve the pleasure of an identifiable desktop object while improving text legibility, keyboard access, and window recovery. An exact visual clone would constrain those improvements. Use original artwork and branding; track provenance and permission for any bundled third-party assets.

## 3. Scope and release priorities

**P0 means required for the first public release. P1 means a follow-up. Explore means no delivery commitment.** A private engineering prototype may implement only a subset of P0.

| P0: first public release | P1: follow-up | Explore |
| --- | --- | --- |
| Local playback and required format matrix | Classic `.wsz` import | Modern `.wal` compatibility |
| Player, playlist, and 10-band EQ | Optional indexed library module | Executable plug-ins |
| Window snapping and compact mode | Internet radio / URL playback | Music-service integration |
| Custom skin import/export and three original skins | Richer skin authoring tool | Online skin marketplace |
| Simple color/accent customization | ReplayGain and crossfade | Advanced visualizers |
| Gapless playback for supported fixtures | Album-art module | Exclusive output / automatic DAC switching |
| Finder opening, keyboard and media controls | Additional codecs and multichannel support | Cross-platform versions |
| Session restoration and accessibility | Intel build if demand warrants | Sync and accounts |

No account, subscription service integration, cloud upload, library scan, or network connection is required to play local files. Tag editing, CD ripping, video playback, and audio conversion are outside the initial product.

Proposed platform baseline: **macOS 14+, Apple silicon**. This is a scope choice to validate in the engineering spike, not a claim about current Apple support policy. Prefer a signed, notarized direct-download app for the initial release; evaluate App Store distribution separately. Design file access to work within App Sandbox from the start.

## 4. Interface concept

### Default skin: Studio Graphite

An original dark graphite chassis, shallow beveled controls, restrained metallic edges, and an amber display. Use a monospaced system font for time and technical information, and a readable system font for track names. Keep the nostalgic texture in framing and controls, not in tiny text.

Two additional bundled skins prove the system: **Paper** (light, flat, warm gray) and **Terminal** (dark, green accents, optional pixel-style decoration). All use the same control semantics and support the same states.

Initial layout targets are in macOS points, not physical pixels:

| Module | Default size | Behavior |
| --- | --- | --- |
| Player | 360 × 160 pt | Fixed proportions; global scale 100%, 125%, 150%, 200% |
| Equalizer | 360 × 160 pt | Same width and scale as player |
| Playlist | 360 × 300 pt | Resizable; minimum 360 × 180 pt at 100% |
| Compact player | 360 × 40 pt | Transport, title, time, and expand action |

Start with player above playlist; EQ is hidden until requested. A fully expanded stack is player → EQ → playlist. Detached playlist can be wider for long names. A “Reset Layout” command returns all windows to a visible position on the current screen.

Conceptual layout, not final artwork:

```text
┌ MIOAMP ──────────────────────── − × ┐
│ 03:42     Artist — Track title        │
│ ▂▅▇▃▆▂    FLAC · 44.1 kHz · Stereo   │
│ ───────────────●───────────────────   │
│ ⏮  ▶/Ⅱ  ■  ⏭     Volume ━━━━━●━━    │
│ Shuffle  Repeat     EQ  List  Skins   │
└──────────────────────────────────────┘
┌ EQUALIZER ─── On / Bypass ─ Preset ──┐
│ Preamp   │ │ │ │ │ │ │ │ │ │        │
│          31 …………………… 16k             │
└──────────────────────────────────────┘
┌ PLAYLIST ───────────── Search ───────┐
│ ▶ 01  Artist — Track title      4:12 │
│   02  Artist — Next track       3:55 │
│   03  Artist — Another track    5:06 │
│ + Add    Save    3 tracks · 13:13    │
└──────────────────────────────────────┘
```

### Interaction rules

- **Open:** File → Open or Finder Open With replaces the current playback list and starts the first playable item. Provide “Add to Playlist” as a separate action.
- **Drop:** files/folders onto the playlist append in deterministic order without interrupting playback. Dropping onto an empty player loads and starts playback; dropping onto a populated player appends and shows feedback.
- **Folders:** recursively include supported files; use natural relative-path order. Preserve explicit playlist order. Never scan unrelated folders.
- **Select/play:** single-click selects; double-click or Return plays. Selection and currently playing status remain visually distinct.
- **Transport:** Play resumes; Pause retains position; Stop resets position to zero. Previous restarts after three seconds, otherwise moves to the previous item. Next follows the active playback order.
- **Shuffle/repeat:** shuffle maintains a separate traversal history without rearranging the visible list. Repeat cycles Off → All → One. Previous follows actual playback history. Manual Next still advances when Repeat One is selected.
- **Filter:** search filters visible playlist rows; it does not change playback order. “Reveal Playing Track” clears a hiding filter when needed.
- **Remove:** removing a playing item lets it finish, then advances to the next surviving item. Clearing the list stops playback. Removing rows never deletes source files; support Undo for list edits.
- **Windows:** snap within a proposed 10 pt threshold. Moving the player moves its connected group; dragging a secondary module detaches it. Closing a secondary module hides it. Closing the player hides all modules while audio continues; Dock activation restores them. Quit stops playback.
- **Restore:** persist queue, selected skin, module layout, volume, EQ, and position; relaunch paused. Restore accessible windows after display changes. Always-on-top is opt-in and defaults off.

Keyboard baseline: Space play/pause when not editing text; Command-O open; Command-Shift-O add; Command-F playlist search; Command-comma settings. Every control must also be reachable through native menus or keyboard focus. Resolve shortcut collisions during prototype testing.

### Essential journeys

1. **First play:** launch → “Drop audio here” / Open Files → playback begins → metadata fills in asynchronously. No onboarding gate.
2. **Album listening:** add folder → verify order → play → gapless transitions → restore paused at the same position on next launch.
3. **Personalization:** open Skins → preview → apply → audio continues → customize accent → export a shareable package.
4. **Missing file:** unavailable row shows a reason → skip without repeated dialogs → Locate File or reconnect volume → resume normally.

## 5. Playback and format requirements

“Modern formats” must be a tested codec-and-container promise, not a list of filename extensions. Apple exposes audio file types through AVFoundation, but a file-type identifier alone is not proof of a complete decoder or gapless pipeline. Validate each combination on every supported macOS version. [Apple AVFileType](https://developer.apple.com/documentation/avfoundation/avfiletype)

| P0 codec | Required container / extension | Minimum fixture coverage |
| --- | --- | --- |
| MP3 | MPEG audio, `.mp3` | CBR/VBR, ID3v2.3/v2.4, tagged gapless album |
| AAC-LC and HE-AAC | MPEG-4 `.m4a`; ADTS `.aac` | Both containers; correct duration and seeking |
| Apple Lossless (ALAC) | MPEG-4 `.m4a` | 16/24-bit; album transitions |
| FLAC | Native `.flac` | 16/24-bit; 44.1–192 kHz fixtures; embedded art |
| PCM | `.wav`, `.aif`, `.aiff` | 16/24-bit integer; 32-bit float WAV |
| Vorbis | Ogg `.ogg`, `.oga` | Metadata, seeking, chained-stream handling |
| Opus | Ogg `.opus`, `.ogg` | Pre-skip/end trimming, seeking, metadata |

P0 guarantees mono/stereo for these combinations. Detect unsupported multichannel files and explain the limitation; do not play an incorrect channel mapping. Protected/DRM files, WMA, DSD, tracker modules, unusual container variants, and other AAC profiles are not initial guarantees. Extension sniffing must be confirmed by content inspection.

Opus and Vorbis should have explicit fallback decoder plans. Xiph provides `libopusfile` for Ogg Opus and `libvorbisfile` for Vorbis; these avoid equating OS codec availability with support for a particular container. Evaluate current releases and dependency licenses before adoption. [Opusfile documentation](https://www.opus-codec.org/docs/opusfile_api-0.4/), [Vorbisfile documentation](https://xiph.org/vorbis/doc/vorbisfile/index.html)

| ID | P0 requirement | Acceptance evidence |
| --- | --- | --- |
| AUD-01 | Play/pause/stop/seek/next/previous for the format matrix | Fixture suite checks playback, duration, seek position, end-of-file, and errors |
| AUD-02 | Gapless album playback | Split contiguous reference audio into lossless tracks and tagged MP3/AAC fixtures; captured output has no inserted/dropped boundary samples at matched rates after specified codec trimming |
| AUD-03 | Responsive, bounded decoding | Stream decoded buffers; do not load entire long recordings into RAM; seek in a two-hour VBR file without blocking UI |
| AUD-04 | 10-band EQ with preamp, bypass, presets, reset | Proposed bands: 31/62/125/250/500 Hz, 1/2/4/8/16 kHz; ±12 dB; verify filter response and bypass; smooth changes without clicks |
| AUD-05 | Prevent avoidable overload | Default preamp 0 dB; provide headroom guidance/clip indicator and a documented output protection stage; measure distortion with boosted fixtures |
| AUD-06 | Handle output and sleep events | Follow system output; pause on output loss/headphone disconnect; never unexpectedly resume through speakers; retain position after sleep |
| AUD-07 | Isolate malformed files | Skip unreadable items with a visible reason; stop after one exhausted queue pass instead of cycling forever |

Gapless guarantees require usable encoder delay/padding information for lossy files. Mixed sample-rate transitions require an engineering test before promising sample-continuous results. Preserve musical silence already in files; do not apply silence removal. Crossfade is separate and deferred. Do not claim bit-perfect output: EQ, volume, conversion, and the system mixer can change samples.

Read title, artist, album, track/disc number, duration, and available artwork. Fall back to filename; show unknown technical values as unavailable. Metadata parsing and artwork decoding must be bounded and asynchronous. P0 reads tags but never rewrites them.

## 6. Playlist and persistence requirements

| ID | Requirement | Acceptance evidence |
| --- | --- | --- |
| LIST-01 | Add/reorder/remove/select multiple tracks; support duplicates | Queue identity is independent of file identity; editing does not restart playback |
| LIST-02 | Import/export M3U and UTF-8 M3U8; import PLS | Preserve order and supported local paths; resolve relative paths against playlist location; flag remote entries as unsupported in P0 |
| LIST-03 | Keep queue and named saved lists distinct | Saving creates a reusable ordered list; edits to the active queue do not silently overwrite saved lists |
| LIST-04 | Persist and recover state | Force-quit/relaunch preserves last durable queue and settings; interrupted write does not corrupt the store |
| LIST-05 | Retain authorized file access | Relaunch can reopen approved files; stale access offers Locate/Reauthorize without silently removing rows |
| LIST-06 | Stay responsive at 10,000 queue entries | Virtualized rows and incremental metadata; scrolling and transport remain responsive during import |

Playlist paths do not themselves grant filesystem permission. A sandboxed app needs appropriately scoped access, including for related files. Apple documents user-selected file access and persistent bookmarks; bookmark lifecycle and reauthorization belong in the initial design. [Apple sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

## 7. Skinning and customization contract

**P0 is real skinning, not only a color picker.** Users can change panel backgrounds, frame artwork, button-state imagery, slider graphics, text colors, permitted fonts, and visualization colors. Layout follows app-owned templates so essential controls remain usable.

Two levels of customization:

1. **Everyday:** choose a skin, change accent/display colors, choose scale, and save a variation without editing files.
2. **Creator:** export a documented starter package, edit assets and manifest, import/preview locally, and share the resulting file.

Proposed `.mioampskin` format: a ZIP package containing versioned `manifest.json`, preview image, and PNG assets at 1×/2× resolutions. Optional vector assets are deferred until a safe, consistent renderer is selected. Schema describes author, version, license/attribution, color tokens, font roles, asset states, and supported app-owned module templates. Font roles select installed/system fonts; font binaries are not bundled in P0.

The app owns transport actions, focus order, accessible names, hit areas, and layout constraints. A skin may change presentation but cannot remove essential actions, start network requests, execute scripts, or alter audio behavior. This makes customization independent of decoder and playback code.

| ID | Requirement | Acceptance evidence |
| --- | --- | --- |
| SKIN-01 | Import, preview, apply, export, remove | Three visually distinct bundled skins use the public schema, not special-case rendering |
| SKIN-02 | Apply during playback | Switching skins preserves current track, position, queue, volume, and EQ; no audio interruption |
| SKIN-03 | Document the creator workflow | A creator can modify the starter, validate it, and share it without building the app |
| SKIN-04 | Validate packages before activation | Reject traversal paths, symlinks, executable content, unsupported schema versions, corrupt images, and excessive expansion |
| SKIN-05 | Bound resource use | Initial limits: 20 MB compressed, 80 MB expanded, 256 files, 4096 px maximum image dimension; enforce aggregate decoded-image budget as well |
| SKIN-06 | Provide recovery | Invalid skin retains previous skin; missing optional artwork falls back; native menu always offers Reset to Default Skin |
| SKIN-07 | Preserve accessibility | All controls keep semantic labels and focus; high-contrast override and readable font option remain available across skins |

**Legacy import is P1.** Prototype a `.wsz` adapter after native skinning works. Publish a compatibility matrix for main player, EQ, playlist, fonts, transparency, and cursors; do not advertise universal compatibility. Modern `.wal` skins and executable skin behavior remain out of scope. Users can import their own assets; bundled skins must have documented permission. The native format should not inherit bitmap-era text and scaling constraints.

## 8. Mac integration and accessibility

- Native menu bar, Open/Save panels, Finder Open With, drag-and-drop, Dock behavior, and standard Settings window.
- System media commands and Now Playing metadata should reflect one shared playback state; validate both foreground and background use with other media apps present.
- VoiceOver identifies track, state, button actions, slider values, queue position, and errors. Keyboard-only users can open files, play, seek, manage the queue, operate EQ, and change skins.
- Target at least 28 × 28 pt primary pointer controls at default scale; verify compact mode separately. Scale changes must not require restarting or disturb window groups.
- Default skins target 4.5:1 normal text contrast and visible keyboard focus. Never communicate playing/selected/error state through color alone.
- Respect Reduce Motion: disable marquee and spectrum motion. Offer static truncation plus full-title tooltip/accessibility text.
- App Hide hides every module. Minimize and Spaces behavior must be tested as a coordinated group, including multiple displays and display disconnection.

## 9. Proposed engineering architecture

Use **Swift with AppKit window coordination**, with SwiftUI where it fits Settings and noncritical views. AppKit provides direct control over the unusual multiwindow layout; validate focus, snapping, and accessibility in an early spike. Avoid choosing a web shell before measuring its cost against a small, always-running native utility.

Separate responsibilities:

```text
Finder / menus / media commands / skinned controls
                       ↓
             Shared playback and queue state
                ↙                    ↘
      File access + metadata     Skin + window state
                ↓
      Decoder adapters → PCM buffers
                ↓
      Audio graph → EQ → gain/protection → output
                └→ bounded analysis feed → spectrum
```

Evaluate AVAudioEngine as the output/processing graph and AVAudioUnitEQ as the EQ building block. Decoder adapters make native decoding and bundled fallbacks feed the same PCM path. These are proposed implementation choices, not evidence that a chosen graph automatically delivers gapless playback. [Apple AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine), [Apple AVAudioUnitEQ](https://developer.apple.com/documentation/avfaudio/avaudiouniteq)

Use a serial playback coordinator to control scheduling and cancellation. Decode and parse metadata off the main thread; prebuffer the next item; allocate no UI or file-processing work in the real-time audio callback. Audio rendering must not depend on skin rendering or visualization timing.

Persist versioned track references, queue entry IDs, saved playlists, window groups, and user settings. Keep source media in place. Store security-scoped bookmarks separately from exported portable playlist paths. Bound artwork caches and migrate state explicitly across app versions.

## 10. Quality targets and release gates

These are initial acceptance budgets to confirm during prototyping, measured in a release build on a baseline M1 Mac with 8 GB RAM, local SSD, and the supported OS matrix. Record actual measurements before advertising performance.

| Area | Proposed target / test |
| --- | --- |
| Startup | Interactive player within 1.5 s at p95 over 20 launches; empty and restored 10,000-track queue |
| Playback start | Local ordinary file audible within 300 ms at p95 over 30 opens, excluding permission dialogs and unavailable volumes |
| UI | Transport input feedback within 100 ms; importing metadata must not block it |
| CPU | Typical stereo playback below 5% of one CPU core with spectrum off; below 10% with spectrum on; measure five-minute steady state |
| Memory | Under 150 MB resident for 1,000 tracks with bounded artwork cache; no growth trend in an eight-hour run |
| Reliability | Eight-hour mixed-format playback with no app-caused dropout, crash, or stuck state |
| Customization | Repeated skin switching and window dragging while playing causes no dropout |
| Recovery | Missing volume, corrupt file, sleep/wake, output change, stale permissions, and disconnected display all have tested recovery paths |
| Offline/privacy | Playback and installed-skin workflows work with network disabled; no listening-history upload or telemetry by default |

Release gates: all P0 requirement checks pass; format fixtures pass on oldest and newest supported macOS; keyboard/VoiceOver workflows pass; malformed skins cannot write outside their import area; bundled assets and dependencies have recorded provenance; signed distribution is installed and tested on a clean Mac.

Usability target: in a small formative test with five participants, at least four can play a folder, show/hide a module, and change a skin without guidance. Include both nostalgic Winamp users and people unfamiliar with it. Use observation and opt-in feedback rather than requiring analytics.

## 11. Build sequence and uncertainty

| Milestone | Deliverable | Exit criterion |
| --- | --- | --- |
| 1. Feasibility | Throwaway audio/window spikes | Required codec/container fixtures, gapless strategy, file access, and grouped windows demonstrated; blockers documented |
| 2. Playback core | Unskinned working player and queue | Transport, restore, format matrix, output recovery, and basic performance verified |
| 3. Product shell | Player, playlist, EQ, compact mode | Core journeys work with keyboard and VoiceOver; display recovery verified |
| 4. Personalization | Public skin schema, three skins, starter kit | Import/export/live switching and invalid-package recovery pass |
| 5. Release candidate | Polished defaults and distributable build | Quality gates and formative usability test pass |
| 6. Compatibility | Optional `.wsz` adapter prototype | Measured coverage determines whether it ships in a follow-up |

No calendar estimate is committed before milestone 1; decoder integration and window behavior are the main unknowns.

| Risk | Mitigation / decision trigger |
| --- | --- |
| Native decoder accepts a codec but not the expected container | Verify matrix early; use a narrow bundled decoder where needed |
| Gapless trimming or scheduling differs across formats | Use captured-output fixtures before UI polish; explicitly qualify unsupported cases |
| Retro density harms usability | Validate default sizing with actual users; retain scaling, readable text, and native menus |
| Skin system grows into a programming platform | Keep P0 declarative and template-based; require a separate product decision for executable extensions |
| Mac multiwindow focus/Spaces behavior feels unreliable | Prototype before final architecture; simplify grouping if necessary |
| Legacy skins consume the release | Keep `.wsz` import outside P0; independently measure compatibility |

## 12. Decisions to revisit after the first prototype

These do not block design exploration; recommended defaults above allow implementation planning to proceed.

| Decision | Recommended default | Revisit when |
| --- | --- | --- |
| Fidelity | Original retro-inspired design | User testing indicates exact classic geometry is central |
| Legacy skins | P1 | Existing `.wsz` collections become a launch requirement |
| Library | Queue and saved playlists first | Folder-based listening becomes cumbersome in testing |
| Platform | Apple silicon, macOS 14+ | Actual audience requires Intel or older systems |
| Distribution/business model | Direct download; monetization undecided | Packaging and launch planning begin |
| Output sophistication | Follow system device; stereo focus | Audience needs DAC-specific control or multichannel |

The first concrete design review should compare the three proposed skin directions at actual size, with player-only, stacked, detached, and compact states. The first engineering review should demonstrate the audio matrix and a gapless album before committing to the complete UI implementation.
