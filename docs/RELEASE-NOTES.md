# MacAmp MVP candidate 0.1.0

The project and application are now named MacAmp. The app bundle, executable, menus, windows, package products, bundle identifier, documentation, and skin-package extension use the new name. On first launch, MacAmp copies missing sessions, playlists, and installed skins from the former ChuckAmp Application Support directory. Existing `.chuckskin` packages remain importable; new exports use `.macampskin`.

This build expands the accepted prototype into an MVP candidate with the full tested audio matrix, hardened skin packages, portable and named playlists, media-key/Now Playing integration, full session migration, interface scaling, and recovery actions.

New user-facing features include the Terminal skin, saved accent variations, `.macampskin` import/export/remove, creator-starter export, M3U/M3U8 import/export, PLS import, named playlists, playlist Undo/search/reveal, Locate/Reauthorize, EQ presets with limiter indication, Finder document handling, and 100/125/150 percent interface scales.

The September 26 maintenance update fixes restored local files reporting that authorization was required after an ad-hoc development rebuild. It also adds Clear Playlist to the Edit menu and a `CLR` playlist control; clearing is persisted and can be undone.

The same update preserves user-resized window frames when queue selection, search, EQ state, or skin changes refresh a module. Studio Graphite buttons now use explicit skin foreground, background, accent, and border colors so every control remains visible regardless of the macOS appearance.

The stabilization pass makes interface scaling apply to typography, layout spacing, and control hit targets as well as window dimensions. Attached modules remain flush at every supported scale, Reset Layout is stable with long metadata, playlist resize events persist across relaunch, and closing the equalizer now closes the gap above the playlist.

The default modular stack now reserves a 200-point content height for the equalizer, giving its sliders a usable adjustment range at 100%. The default playlist height was reduced by the same 40 points so the complete stack keeps the same screen footprint, and undersized equalizer frames from earlier sessions are upgraded when restored.

Known limits:

- ADTS AAC and independently encoded Vorbis pairs do not receive a gapless guarantee because their fixtures do not expose reliable end trimming.
- Mixed-sample-rate transitions work, but sample continuity is not promised across the converter boundary.
- Chained Ogg logical streams and input above two channels are rejected with a specific error.
- The candidate is ad-hoc signed for local use. Public distribution still requires an authorized Developer ID signing identity and notarization.
- macOS 14, VoiceOver, multiple displays/Spaces, removable volumes, hardware route changes, and participant usability checks remain external validation work.
