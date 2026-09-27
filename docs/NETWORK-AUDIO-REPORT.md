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
