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

No runtime codec dependency is required for the prototype formats. For the full MVP, keep decoder adapters behind the same contract. Test native ALAC, AIFF, ADTS AAC, HE-AAC, high-rate/24-bit FLAC, and float WAV next. Treat Ogg Vorbis and Ogg Opus as blocked until native coverage is measured; if missing or inconsistent, request narrowly scoped `libvorbisfile` and `libopusfile` dependencies with license and packaging review.

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

There were no inserted or dropped timeline frames and no silent hole at either boundary. The PCM delta is consistent with the next sample of the continuous sine. The MP3 result proves that this encoder/native-decoder pair honors its LAME/Xing trimming and can be scheduled without a gap; it does not claim decoded lossy samples equal the original PCM. AAC album-pair boundary coverage remains for T4.

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
.build/debug/AudioProbe engine-pair Tests/Fixtures/Audio/boundary-01.mp3 Tests/Fixtures/Audio/boundary-02.mp3
.build/debug/AudioProbe engine-stress Tests/Fixtures/Audio/tone-aac.m4a
.build/debug/AudioProbe engine-failure
```

`play` uses the current default output and runs until the scheduled file completes. The other commands emit JSON suitable for CI capture.

## Known limits before production integration

- Only this macOS/toolchain combination has actual codec evidence. The oldest supported macOS 14 release still needs the same matrix.
- This spike uses whole-file scheduling only for boundary proof. T4 must implement bounded decode/prefetch scheduling, cancellation, generations, and file-access lease lifetime behind `AudioEngineClient`.
- Matching sample rate and channel count are required for the proven sample-time boundary strategy. Mixed-rate transitions need a measured converter strategy before any gapless promise.
- Corrupt/truncated input, long VBR files, mono, 24-bit/high-rate FLAC, and unsupported multichannel error reporting need fixture coverage.
- The probe reports packet table trimming but does not parse container-specific metadata beyond what Core Audio exposes.
- Real output reconfiguration and sleep/wake tests were not run.
