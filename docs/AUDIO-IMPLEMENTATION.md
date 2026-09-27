# Production audio implementation

Status: T4 prototype implementation complete on the macOS 26 test machine. This document is the integration contract for T7 and records remaining work for T8.

## Integration entry points

Construct `NativeAudioEngineClient` and retain it for the app session. It implements the frozen `AudioEngineClient` protocol directly. The playback coordinator should be the only caller.

1. Create a `NativeAudioDecoder` while its file-access lease is held.
2. Wrap it in `AudioTrackPreparation` with the queue entry ID and current generation.
3. Call `prepare(current:next:)`. This decodes and schedules a bounded initial window, then emits `prepared`.
4. Consume `events` continuously before issuing playback commands so the stream cannot fill while the coordinator is idle.
5. Call transport, next-track, volume, and EQ methods only through the serialized coordinator.
6. Commit queue advancement only for `transitioned` carrying the expected generation. Release the previous file lease after that transition and replaced next-track leases after `updateNext` returns.

The engine accepts decoder existentials and does not own security-scoped access itself. Lease ownership stays with the coordinator as specified by the shared contracts.

## Scheduling and memory bounds

The default decode block is 4,096 frames and each track may retain at most six scheduled buffers. Stereo Float32 therefore uses 192 KiB of scheduled PCM per track, plus small framework overhead. Current and next use approximately 384 KiB of explicitly managed scheduled PCM at the default settings. Decode resumes only after a playback completion returns a buffer slot.

Current and next use separate `AVAudioPlayerNode` lanes connected to the same engine clock. The next lane receives an absolute host start time derived from the current decoded frame length. Replacing next stops and flushes only its lane; current playback is not restarted. On natural completion, the matching next token is promoted and a generation-tagged transition event is emitted.

Each player lane connects to the track mixer using the decoder's noninterleaved Float32 sample rate and channel count. The mixer converts that declared source format to the hardware output rate. A nil connection format incorrectly interpreted 192 kHz buffers at a 48 kHz device rate, producing 4× slow playback; explicit per-lane formats also allow adjacent tracks to use different rates.

Every prepare, seek, next replacement, stop, and output reset changes the track token. Late buffer completions from old tokens are ignored. Generation checks reject stale transport and next-prefetch requests before they mutate active state.

## Position and transport

Position events are sampled from `AVAudioPlayerNode.playerTime(forNodeTime:)`, tied to rendered audio frames. Buffer-completion counts provide a fallback when the render timestamp is temporarily unavailable. The 100 ms event cadence only throttles presentation updates; elapsed position is not synthesized from wall-clock time.

Seek stops and flushes the current lane, seeks the decoder by frame, refills the bounded window, resets next prefetch, and resumes only if playback was active. Stop seeks and stages the current track at frame zero. Pause preserves current scheduled buffers but rewinds next prefetch so resume can assign a fresh host start time.

## Processing graph

```text
current player ─┐
                ├─ track mixer → 10-band EQ/preamp → peak limiter → main volume → output
next player ────┘
```

The EQ uses the contract frequencies and clamps band/preamp gains to ±12 dB. Changes interpolate over roughly 36 ms to reduce zipper noise. Bypass leaves the rest of the graph active. Reset is represented by the contract default `EQSettings()`.

`EqualizerPreset` supplies Flat, Rock, Pop, Jazz, Classical, and Bass Boost through ordinary `EQSettings`; presets do not bypass the shared command/state path.

An Apple `AUPeakLimiter` follows the EQ to protect against avoidable overload from positive preamp and band combinations. Boosted output is processed and must never be described as bit-perfect. Final QA should add captured clipping/distortion measurements across preset and preamp extremes.

`outputProtectionStatus()` is the documented concrete-engine indicator. It reports whether positive requested EQ/preamp gain may cause the limiter to reduce gain. The Apple limiter does not expose sample-accurate reduction through this graph, so the API does not pretend to be a measured clip meter.

The offline overload probe fed a 0.9-peak sine through +12 dB gain. Its predicted unprotected peak was 3.582965; the captured post-limiter peak was 0.732994. This confirms active protection for the measured steady signal, though it is not a proof for every transient shape.

Volume is clamped to 0...1 at the main mixer.

## Output and sleep safety

The engine observes `AVAudioEngineConfigurationChange` and the macOS sleep notification. If either occurs with a prepared track, it stops both lanes, records the rendered frame, refills from that point, emits `outputUnavailable`, and does not automatically resume. The coordinator should present the paused/output-unavailable state and require explicit play. This avoids an automatic route change resuming through speakers.

Actual headphone removal, device disconnection, sleep/wake, and multiple-output-device testing still require manual hardware validation. A configuration change is intentionally conservative and may pause for benign device format changes.

## Typed failures

- Stale operations: `cancelled`
- Invalid seek or malformed PCM: `corrupt` or `unsupported`, as appropriate
- Mono/stereo policy violations: `unsupported`
- Output notification: `outputUnavailable` event
- Decoder errors during asynchronous refill: `failed` event tagged with the affected generation

The coordinator remains responsible for bounded corrupt-file traversal across the queue; the engine reports one failure for the affected generation and never selects another queue item itself.

## Validation evidence

Commands run successfully in a serial process outside the command sandbox, where macOS permits AudioComponent discovery:

```sh
swift build --product AudioProbe
.build/debug/AudioProbe engine-play Tests/Fixtures/Audio/tone-aac.m4a
.build/debug/AudioProbe engine-play Tests/Fixtures/Audio/tone-44k.flac
.build/debug/AudioProbe engine-pair Tests/Fixtures/Audio/boundary-01.mp3 Tests/Fixtures/Audio/boundary-02.mp3
.build/debug/AudioProbe engine-stress Tests/Fixtures/Audio/tone-aac.m4a
.build/debug/AudioProbe engine-failure
.build/debug/AudioProbe protection
.build/debug/AudioProbe seek Tests/Fixtures/Audio/tone-vbr-10m.mp3 599.5
```

Observed results:

- AAC and FLAC production playback reached the expected `ended` event.
- The bounded two-track MP3 run emitted `transitioned` for track two and then `ended`.
- Rapid play → seek → pause → play → stop → play, with live volume, EQ, and EQ-reset changes, completed at generation 12 with zero failure events; old buffer callbacks did not terminate or mutate the new generation.
- A synthetic decoder read failure produced a `failed` event with code `corrupt` and generation 21.
- The ten-minute VBR MP3 reported 26,460,000 decoded frames and successfully sought to frame 26,437,950 (599.5 seconds), then returned a bounded 1,024-frame read.
- T1 captured-output analysis remains the sample-boundary evidence: WAV and tagged MP3 pairs rendered exactly 88,200 expected frames with no silent hole.

Tests that instantiate AudioComponents carry an explicit disabled Swift Testing trait because the parallel package-test sandbox can abort inside `AVAudioPlayerNode` before Swift can catch an error. They remain compile-checked. Serial `AudioProbe` commands are the executable graph evidence and prevent `scripts/test.sh` from crashing.

The final repository run of `./scripts/test.sh` passed 73 tests with zero failures; the five explicitly environment-dependent AudioComponent cases were skipped as designed and covered by the serial probes above.

## Remaining limits

- Gapless scheduling is proven for matched-rate tracks. Mixed-rate transitions remain unpromised pending captured-output analysis.
- Output loss and sleep handling are implemented but need hardware/manual evidence.
- The full MVP codec matrix, two-hour seek fixture, AAC/ALAC/FLAC/Opus boundary pairs, corrupt/truncated corpus, chained Ogg rejection, silence preservation, and channel policy now have fixtures and macOS 26 evidence.
- The oldest-supported-macOS run remains outstanding; native Ogg support must be rechecked there before final dependency decisions.
- The position cadence and buffering defaults should be profiled in a release build on the baseline M1 machine before becoming fixed product promises.
