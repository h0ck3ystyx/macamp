# Audio buffering diagnostics

MioAmp writes focused playback diagnostics to the macOS Unified Log with subsystem `io.github.h0ck3ystyx.mioamp` and category `AudioBuffer`. Normal playback produces one buffer-plan entry for the current track and one for its prefetched successor. Additional entries appear only when a decoder or storage read is slow, the scheduled queue is nearly empty, or playback runs out of queued data.

To watch the log while reproducing a stutter:

```sh
log stream --style compact --level info \
  --predicate 'subsystem == "io.github.h0ck3ystyx.mioamp" AND category == "AudioBuffer"'
```

To collect the previous ten minutes after a stutter:

```sh
log show --last 10m --info --style compact \
  --predicate 'subsystem == "io.github.h0ck3ystyx.mioamp" AND category == "AudioBuffer"'
```

The messages mean:

- `Buffer plan`: codec, source rate, frames per block, block count, and total queued coverage. Production defaults target eight seconds.
- `Slow decode/read`: one storage or decoder read took at least 250 ms. Repeated entries for files on `/Volumes` strongly suggest network or external-volume latency.
- `Buffer low water`: playback has two or fewer blocks left. At the default 250 ms block size, less than 0.5 seconds remains.
- `Buffer underrun`: the active queue reached zero before end-of-stream. This is direct evidence that the audible interruption came from exhausted source data.

Entry IDs are included so plan, latency, and underrun messages can be correlated without logging file paths or track names.
