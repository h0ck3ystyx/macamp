# Audio feasibility report

Status: prototype audio gate passed on the machine below. These results establish a viable native path; they are not a claim about the full MVP format matrix or every supported macOS release.

## Test environment

- macOS 26.5.2 (25F84), Apple silicon (`arm64`)
- Xcode 26.2 (17C52), Swift 6.2.3
- FFmpeg 9.0.1 was used only to generate synthetic redistributable fixtures. It is not a runtime dependency.
- Machine-readable results: `Tests/Fixtures/Audio/results-macos26.json`

The command sandbox blocks system AudioComponent discovery. Core Audio execution was therefore run outside that sandbox. The built app runs in the normal macOS process environment, where the components loaded successfully.

## Decision

Use `ExtAudioFile` as the first native decoder adapter and `AVAudioEngine` as the output/processing graph. `NativeAudioDecoder` exposes bounded interleaved Float32 reads and frame-accurate seeks through the shared `Decoder` contract. It rejects input above two channels instead of silently applying an undefined mapping.

Schedule current and next tracks on one `AVAudioPlayerNode` timeline using explicit sample times when their processing formats match. Core Audio reports decoded frame counts after codec priming/remainder handling. The raw packet table remains diagnostic metadata; the production path must not subtract those values a second time.

Use `AVAudioUnitEQ` for the ten-band equalizer. A focused 1 kHz test requested +12 dB and measured +11.990 dB in offline rendering, so the component provides the required audible processing. T4 still needs parameter smoothing, preamp, bypass, reset, headroom/protection, and response tests for all ten proposed bands.

Native `ExtAudioFile` decodes ALAC, AIFF, AAC-LC/HE-AAC in MPEG-4 and ADTS, float WAV, Ogg Vorbis, and Ogg Opus. A later macOS 26 update began rejecting both FLAC and some real-library MP3 files during Float32 client conversion with Core Audio `fmt?` (`1718449215`). MacAmp therefore uses pinned, bounded `dr_flac` and `dr_mp3` adapters for FLAC and MP3 while retaining the shared decoder contract for every format. The adapters accept ordinary metadata layouts, including ID3-prefixed FLAC and ID3-tagged MP3, and preserve bounded reads and frame seeks. Repeat the full matrix on macOS 14.

## Prototype format results

Each two-second fixture was fully decoded in 4,096-frame bounded reads and then sought to decoded frame 55,125 (1.25 seconds), followed by a successful 1,024-frame read.

| Fixture | Native codec ID | Decoded frames | Decode | Seek |
| --- | --- | ---: | --- | --- |
| PCM 16-bit stereo WAV | `lpcm` | 88,200 | Pass | Pass |
| FLAC stereo | `flac` | 88,200 | Pass | Pass |
| AAC-LC in M4A | `aac ` | 88,200 | Pass | Pass |
| VBR MP3 with ID3v2.3 | `.mp3` | 88,200 | Pass | Pass |
| CBR MP3 with ID3v2.4 | `.mp3` | 88,200 | Pass | Pass |

Packet table inspection reported AAC delay/padding of 1,024/888 frames and MP3 delay/padding of 576/1,080 frames. The native decoded length was exactly the 88,200 valid source frames in each case. FLAC exposed a packet-table remainder despite decoding exactly the expected source length, which reinforces treating packet-table fields as diagnostics rather than unconditional trimming instructions.

## Two-track scheduling and boundary evidence

The fixture generator split one continuous 44.1 kHz sine source at exactly frame 44,100. `AudioProbe boundary` scheduled both files into a single offline `AVAudioEngine` timeline and captured the rendered boundary.

| Pair | Expected/rendered frames | Boundary delta | Near-boundary peak | Result |
| --- | ---: | ---: | ---: | --- |
| PCM WAV | 88,200 / 88,200 | 0.005554 | 0.074524 | Pass |
| Tagged VBR MP3 | 88,200 / 88,200 | 0.005402 | 0.074585 | Pass |

There were no inserted or dropped timeline frames and no silent hole at either boundary. The PCM delta is consistent with the next sample of the continuous sine. The MP3 result proves that this encoder/native-decoder pair honors its LAME/Xing trimming and can be scheduled without a gap; it does not claim decoded lossy samples equal the original PCM. Additional codec pairs are reported below.

## Full P0 matrix evidence

T8 expanded the generated matrix and exercised full bounded decode plus seek for every row. The exact values are in `Tests/Fixtures/Audio/results-macos26.json`.

| Codec/container | Fixture detail | Native result |
| --- | --- | --- |
| PCM/WAVE | 16-bit and float32 | Decode/seek pass |
| PCM/AIFF | 24-bit, 96 kHz | Decode/seek pass |
| FLAC | 16/24-bit, 44.1/96/192 kHz | Decode/seek pass |
| ALAC/M4A | 16-bit and 24-bit/96 kHz | Decode/seek pass |
| AAC-LC/M4A | tagged trimming | 88,200 valid frames; pass |
| AAC-LC/ADTS | no packet-table trim | 90,112 decoded frames; playback/seek pass, gapless not promised |
| HE-AAC/M4A | tagged trimming | 88,200 valid frames; pass |
| HE-AAC/ADTS | no packet-table trim | 94,208 decoded frames; playback/seek pass, gapless not promised |
| MP3 | CBR/VBR, ID3v2.3/v2.4 | Decode/seek pass |
| Vorbis/Ogg | tagged stereo | 88,256 decoded frames; playback/seek pass |
| Opus/Ogg | pre-skip/end trim | 96,000 valid frames; playback/seek pass |

Content and container checks do not rely on the suffix alone. A WAVE payload renamed `.mp3` is rejected rather than accepted from its extension. Six-channel FLAC is rejected with the explicit mono/stereo policy. Corrupt and header-truncated MP3 fixtures fail without entering playback.

The Ogg parser walks page headers with constant memory and rejects chained logical bitstreams. Native decoding otherwise stops after the first logical stream, which would silently omit audio. P0 policy is therefore explicit rejection; supporting chained albums would require a decoder that exposes and transitions logical links.

The two-hour VBR MP3 fixture is 16 kHz mono to keep the generated repository asset compact. It reports 115,201,152 decoded frames and a seek to 7,199.25 seconds returned a bounded 1,024-frame read. It tests indexing and memory behavior, not fidelity.

### Expanded boundary results

| Pair | Rendered frames | Boundary delta | Result |
| --- | ---: | ---: | --- |
| FLAC | 88,200 | 0.005554 | Continuous |
| ALAC | 88,200 | 0.005554 | Continuous |
| AAC-LC/M4A | 88,200 | 0.005981 | Continuous for tagged fixture |
| HE-AAC/M4A | 88,200 | 0.005702 | Continuous for tagged fixture |
| Opus/Ogg | 96,000 | 0.003902 | Continuous with pre-skip/end trim |
| Vorbis/Ogg | 88,320 | 0.087503 | Limited; independent files contain 60 extra decoded frames each |

ADTS AAC contains no packet table in these fixtures, so it exposes encoder delay/padding and cannot receive a gapless guarantee. The independently encoded Vorbis pair also lacks a reliable application-level end-trim guarantee and shows a discontinuity. MacAmp preserves all source samples, including intentional silence, rather than applying silence removal to hide those limits.

A 44.1 kHz WAV → 48 kHz Opus production-engine pair emitted the correct transition and end events. Sample-continuous mixed-rate output is not claimed because it passes through sample-rate conversion and was not compared against a single converted reference timeline.

## Output graph observations

The native graph started against the current two-channel, 48 kHz output. Device loss, headphone disconnect, sleep/wake, and live sample-rate/device changes were not exercised because they require hardware or system event manipulation. T4 should observe engine configuration changes and default-device notifications, stop safely on output loss, preserve position, rebuild the graph off the render callback, and require an explicit user play after a potentially unsafe route change.

`AudioProbe play` also scheduled the generated AAC/M4A fixture to the current output and reached its completion callback successfully.

## Probe usage

Generate fixtures:

```sh
scripts/generate-audio-fixtures.sh
```

Build and run:

```sh
swift build --product AudioProbe
.build/debug/AudioProbe inspect Tests/Fixtures/Audio/tone-aac.m4a
.build/debug/AudioProbe decode Tests/Fixtures/Audio/tone-vbr-id3v23.mp3
.build/debug/AudioProbe seek Tests/Fixtures/Audio/tone-44k.flac 1.25
.build/debug/AudioProbe boundary Tests/Fixtures/Audio/boundary-01.wav Tests/Fixtures/Audio/boundary-02.wav
.build/debug/AudioProbe eq
.build/debug/AudioProbe output
.build/debug/AudioProbe play /path/to/file.mp3
.build/debug/AudioProbe engine-play Tests/Fixtures/Audio/tone-aac.m4a
.build/debug/AudioProbe engine-soak /path/to/network-file.flac 30
.build/debug/AudioProbe engine-pair Tests/Fixtures/Audio/boundary-01.mp3 Tests/Fixtures/Audio/boundary-02.mp3
.build/debug/AudioProbe engine-stress Tests/Fixtures/Audio/tone-aac.m4a
.build/debug/AudioProbe engine-failure
.build/debug/AudioProbe protection
```

`play` uses the current default output and runs until the scheduled file completes. The other commands emit JSON suitable for CI capture.

## Known limits before production integration

- Only this macOS/toolchain combination has actual codec evidence. The oldest supported macOS 14 release still needs the same matrix, especially native Ogg support.
- This spike uses whole-file scheduling only for boundary proof. T4 must implement bounded decode/prefetch scheduling, cancellation, generations, and file-access lease lifetime behind `AudioEngineClient`.
- Matching sample rate and channel count are required for the proven sample-time boundary strategy. Mixed-rate transitions need a measured converter strategy before any gapless promise.
- Actual output-device loss, sleep/wake, and oldest-OS behavior still need hardware coverage.
- The probe reports packet table trimming but does not parse container-specific metadata beyond what Core Audio exposes.
- Real output reconfiguration and sleep/wake tests were not run.
