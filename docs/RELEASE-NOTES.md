# ChuckAmp MVP candidate 0.1.0

This build expands the accepted prototype into an MVP candidate with the full tested audio matrix, hardened skin packages, portable and named playlists, media-key/Now Playing integration, full session migration, interface scaling, and recovery actions.

New user-facing features include the Terminal skin, saved accent variations, `.chuckskin` import/export/remove, creator-starter export, M3U/M3U8 import/export, PLS import, named playlists, playlist Undo/search/reveal, Locate/Reauthorize, EQ presets with limiter indication, Finder document handling, and 100/125/150 percent interface scales.

The September 26 maintenance update fixes restored local files reporting that authorization was required after an ad-hoc development rebuild. It also adds Clear Playlist to the Edit menu and a `CLR` playlist control; clearing is persisted and can be undone.

Known limits:

- ADTS AAC and independently encoded Vorbis pairs do not receive a gapless guarantee because their fixtures do not expose reliable end trimming.
- Mixed-sample-rate transitions work, but sample continuity is not promised across the converter boundary.
- Chained Ogg logical streams and input above two channels are rejected with a specific error.
- The candidate is ad-hoc signed for local use. Public distribution still requires an authorized Developer ID signing identity and notarization.
- macOS 14, VoiceOver, multiple displays/Spaces, removable volumes, hardware route changes, and participant usability checks remain external validation work.
