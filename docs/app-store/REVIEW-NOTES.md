# App Review notes — MioAmp 1.0

MioAmp is an offline, sandboxed player for audio files selected by the user. It has no account, login, purchase, subscription, network service, or hidden feature.

To exercise the app:

1. Click **OPEN** or choose **File > Open…**, then select one or more reviewer-owned audio files. The app accepts MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF, Ogg Vorbis, and Opus.
2. Use the transport controls or the **Playback** menu. Drag the upper progress slider to seek and the lower volume slider to change volume.
3. Click **EQ** or choose **Window > Show Equalizer** to test the ten-band equalizer and presets.
4. Click **LIST** or choose **Window > Show Playlist**. Reorder tracks by dragging rows. **Edit > Clear Playlist** clears all items.
5. Choose **Window > Show Visualization** and select among the bundled original visualization presets.
6. Choose **Skins > Studio Graphite**, **Paper**, or **Terminal**. The import/export items in that menu operate on MioAmp's documented `.mioampskin` package format.
7. Quit and reopen the app. The queue and interface state restore paused. macOS security-scoped bookmarks preserve access to files the reviewer selected. If a file moved, select it and use **File > Locate Selected File…**.

The app intentionally rejects remote URLs in imported playlists. Network volumes work only when mounted in Finder and explicitly selected by the user. A disconnected volume produces an unavailable item rather than attempting a network connection.

No demo account is needed. Review contact name, email, and international-format phone number must be supplied by the account holder in App Store Connect.
