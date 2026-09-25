#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/Tests/Fixtures/Audio"
mkdir -p "$OUT"
FFMPEG=${FFMPEG:-ffmpeg}
COMMON="-hide_banner -loglevel error -y"

# Deterministic, generated audio only. The boundary sources are contiguous halves.
$FFMPEG $COMMON -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" -ac 2 -c:a pcm_s16le "$OUT/tone-44k-stereo.wav"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a flac "$OUT/tone-44k.flac"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a aac -b:a 160k -metadata title="Synthetic tone" "$OUT/tone-aac.m4a"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a libmp3lame -q:a 2 -id3v2_version 3 -metadata title="Synthetic tone" "$OUT/tone-vbr-id3v23.mp3"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a libmp3lame -b:a 192k -id3v2_version 4 -metadata title="Synthetic tone" "$OUT/tone-cbr-id3v24.mp3"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=220:sample_rate=44100:duration=600" -ac 2 -c:a libmp3lame -q:a 5 -metadata title="Synthetic long seek fixture" "$OUT/tone-vbr-10m.mp3"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -af atrim=start_sample=0:end_sample=44100 -c:a pcm_s16le "$OUT/boundary-01.wav"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -af atrim=start_sample=44100:end_sample=88200 -c:a pcm_s16le "$OUT/boundary-02.wav"
$FFMPEG $COMMON -i "$OUT/boundary-01.wav" -c:a libmp3lame -q:a 2 -metadata track=1 "$OUT/boundary-01.mp3"
$FFMPEG $COMMON -i "$OUT/boundary-02.wav" -c:a libmp3lame -q:a 2 -metadata track=2 "$OUT/boundary-02.mp3"

cat > "$OUT/manifest.json" <<'JSON'
{
  "provenance": "Generated from FFmpeg's sine filter; no third-party recording is included.",
  "sampleRate": 44100,
  "sourceDurationSeconds": 2,
  "fixtures": [
    {"path":"tone-44k-stereo.wav","codec":"PCM s16","container":"WAVE","prototype":true},
    {"path":"tone-44k.flac","codec":"FLAC","container":"FLAC","prototype":true},
    {"path":"tone-aac.m4a","codec":"AAC-LC","container":"MPEG-4","prototype":true},
    {"path":"tone-vbr-id3v23.mp3","codec":"MP3 VBR","container":"MPEG audio","prototype":true},
    {"path":"tone-cbr-id3v24.mp3","codec":"MP3 CBR","container":"MPEG audio","prototype":true},
    {"path":"tone-vbr-10m.mp3","codec":"MP3 VBR","container":"MPEG audio","durationSeconds":600,"purpose":"bounded long-file seek"},
    {"path":"boundary-01.wav","codec":"PCM s16","container":"WAVE","expectedDecodedFrames":44100},
    {"path":"boundary-02.wav","codec":"PCM s16","container":"WAVE","expectedDecodedFrames":44100},
    {"path":"boundary-01.mp3","codec":"MP3 VBR","container":"MPEG audio","expectedDecodedFrames":44100,"trimming":"LAME/Xing metadata"},
    {"path":"boundary-02.mp3","codec":"MP3 VBR","container":"MPEG audio","expectedDecodedFrames":44100,"trimming":"LAME/Xing metadata"}
  ]
}
JSON

echo "Generated fixtures in $OUT"
