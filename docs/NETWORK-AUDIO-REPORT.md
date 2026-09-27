# Network audio validation

Date: September 27, 2026

Source: `/Volumes/Music/lidarr`

Access: read-only test activity; MacAmp did not modify the library

## Sample

The probe inspected the first 300 supported files returned by a bounded library walk. This is a representative compatibility and buffering sample, not an exhaustive scan of the volume.

| Codec | Sample rate | Files |
| --- | ---: | ---: |
| FLAC | 44.1 kHz | 141 |
| FLAC | 96 kHz | 127 |
| FLAC | 192 kHz | 24 |
| MP3 | 44.1 kHz | 8 |

## Decode and seek checks

Selected files were fully decoded through MacAmp's production decoder in bounded 4,096-frame reads. Long tracks were then reopened and sought to 30 seconds.

| File | Format | Size | Full decode | 30 s seek |
| --- | --- | ---: | ---: | ---: |
| Up on the Mountain | FLAC 44.1 kHz | 36.96 MiB | 4.357 s | 0.020 s |
| Toys in the Attic | FLAC 96 kHz | 73.04 MiB | 6.470 s | 0.035 s |
| Ain't That a Bitch | FLAC 96 kHz | 125.18 MiB | 11.874 s | 0.052 s |
| Amazing | FLAC 192 kHz | 254.57 MiB | 25.863 s | 0.123 s |

The short 192 kHz `Intro` decoded its complete 15.57 MiB stream in 1.809 seconds; a 30-second seek was correctly rejected because the track ends before that point.

The sample exposed two valid-file failures in the Apple system path. `Summer in the City.flac` carries an ID3v2 block before its FLAC marker, and all eight sampled MP3 tracks failed Core Audio's Float32 client-format setup with `fmt?` (`1718449215`). MacAmp now routes `.flac` and `.mp3` files through pinned software decoders. The ID3-prefixed FLAC then decoded all 9,075,780 frames, and all eight MP3 tracks completed full bounded decodes. `Mama Kin.mp3` decoded 11,850,671 frames and passed a 30-second seek to frame 1,323,000.

## Playback buffering

Muted production-engine soaks ran directly from the mounted volume for representative 44.1, 96, and 192 kHz FLAC tracks and a 44.1 kHz MP3 track. Each reached at least 12 seconds of rendered position. The engine scheduled thirty-two 250 ms buffers per lane, which provides eight seconds of decoded coverage at every tested sample rate.

Unified logging recorded one 0.317-second read at 96 kHz and one 0.564-second read at 192 kHz. Those reads exceeded a single block duration but remained well inside the queued coverage. No low-water or underrun event was recorded in any soak.

## Limits

The validation covered a bounded 300-file inventory, selected full-file decodes and seeks, all eight MP3 files in that inventory, and four 12-second playback soaks. Multi-hour playback, disconnect/reconnect behavior, concurrent network load, and the remainder of the library still require longer operational testing.

## Full-volume follow-up

A subsequent read-only walk covered all 9,814 audio directory entries on the volume, totaling 420.76 GiB:

| Codec/container | Files | Sample-rate coverage |
| --- | ---: | --- |
| FLAC | 8,398 | 6,135 at 44.1 kHz; 256 at 48 kHz; 74 at 88.2 kHz; 1,390 at 96 kHz; 543 at 192 kHz |
| MP3 | 1,404 directory entries | 1,358 readable at 44.1 kHz; 25 at 32 kHz; 20 at 48 kHz; one unreadable directory entry |
| PCM WAV | 12 | 44.1 kHz, 16-bit |

Every readable file is stereo. The FLAC set contains 5,414 16-bit and 2,984 24-bit files; 176 FLAC files carry an ID3 block before the FLAC stream. The MP3 set includes 1,242 files with a leading ID3 tag and 161 without one. Durations range from 4.27 seconds to 76.49 minutes. The largest file is a 711.85 MB, 192 kHz FLAC.

All 1,403 readable MP3 files, totaling 10.0 GiB, completed full bounded decoding through MacAmp with zero process or decoder failures. Long-file seeks also passed at 4,500 seconds in the 76-minute MP3 and at 1,000 seconds in a 711.85 MB FLAC. Targeted full decodes passed for 32/44.1/48 kHz MP3, ID3-tagged and untagged MP3, ID3-prefixed FLAC, 16/24-bit FLAC at 44.1/48/88.2 kHz, PCM WAV, and the four-second shortest track.

Muted engine checks passed for the newly discovered 32 kHz MP3 and 88.2 kHz FLAC profiles; the short 48 kHz MP3 reached its natural end. Network reads reached 0.898 seconds during these checks, but the eight-second queue recorded no low-water or underrun event.

### Legacy MP3 timing precision

The full decode pass compared each MP3's initial frame-count estimate with the number of frames actually returned at end of stream. There were 591 exact matches. The other 812 files returned between 1 and 1,152 fewer frames than the initial estimate. The maximum difference is 34.5 ms at 32 kHz, 26.1 ms at 44.1 kHz, and 22.1 ms at 48 kHz. All differences were shortfalls; no decoder returned more audio than advertised.

This does not prevent playback or seeking. It can leave a transition gap of up to the same duration because MacAmp schedules a prefetched next track from the initial frame count. The generated tagged MP3 pair remains sample-continuous, but a broad gapless guarantee is not justified for legacy MP3s whose timing headers are approximate.

### Unreadable network entry

The volume enumerates `Garth Brooks/Sevens/05 Two Piña Coladas.mp3`, but direct lookup and `stat` fail for both NFC and NFD spellings of the name. Other Unicode filenames, curly punctuation, apostrophes, and long paths decoded normally. This appears to be a stale or inconsistent network-filesystem directory entry. MacAmp's existing partial-import behavior should report and skip it rather than stop an album import.

The full follow-up verifies readable headers for every audio entry, full decoding for every readable MP3, and targeted decoding/playback across every distinct profile. It does not perform a 410 GiB full PCM decode of all 8,398 FLAC files, a long-duration playback soak, concurrent server-load simulation, or disconnect/reconnect testing.
