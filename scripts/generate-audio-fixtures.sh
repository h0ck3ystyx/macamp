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
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a aac -b:a 160k -f adts "$OUT/tone-aac-lc.aac"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a alac -sample_fmt s16p "$OUT/tone-alac-16.m4a"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=660:sample_rate=96000:duration=2" -ac 2 -c:a pcm_s24le "$OUT/tone-96k-24.wav"
$FFMPEG $COMMON -i "$OUT/tone-96k-24.wav" -c:a alac -sample_fmt s32p "$OUT/tone-alac-24.m4a"
$FFMPEG $COMMON -i "$OUT/tone-96k-24.wav" -c:a flac -sample_fmt s32 "$OUT/tone-flac-96k-24.flac"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=880:sample_rate=192000:duration=1" -ac 2 -c:a pcm_s24le "$OUT/tone-192k-24.wav"
$FFMPEG $COMMON -i "$OUT/tone-192k-24.wav" -c:a flac -sample_fmt s32 "$OUT/tone-flac-192k-24.flac"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a pcm_f32le "$OUT/tone-float32.wav"
$FFMPEG $COMMON -i "$OUT/tone-96k-24.wav" -c:a pcm_s24be "$OUT/tone-aiff-24.aiff"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a vorbis -strict -2 -q:a 5 -metadata title="Synthetic Vorbis" "$OUT/tone-vorbis.ogg"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a libopus -b:a 128k -metadata title="Synthetic Opus" "$OUT/tone-opus.opus"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=330:sample_rate=48000:duration=1" -ac 2 -c:a libopus -b:a 128k "$OUT/chain-01.opus"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=550:sample_rate=48000:duration=1" -ac 2 -c:a libopus -b:a 128k "$OUT/chain-02.opus"
cat "$OUT/chain-01.opus" "$OUT/chain-02.opus" > "$OUT/chained-opus.opus"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=1" -filter_complex "[0:a]pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0[a]" -map "[a]" -c:a flac "$OUT/multichannel-5_1.flac"
$FFMPEG $COMMON -f lavfi -i "aevalsrc=0:d=0.25:s=44100" -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=1" -f lavfi -i "aevalsrc=0:d=0.25:s=44100" -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1[a]" -map "[a]" -ac 2 -c:a flac "$OUT/silence-bookends.flac"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a libmp3lame -q:a 2 -id3v2_version 3 -metadata title="Synthetic tone" "$OUT/tone-vbr-id3v23.mp3"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -c:a libmp3lame -b:a 192k -id3v2_version 4 -metadata title="Synthetic tone" "$OUT/tone-cbr-id3v24.mp3"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=220:sample_rate=44100:duration=600" -ac 2 -c:a libmp3lame -q:a 5 -metadata title="Synthetic long seek fixture" "$OUT/tone-vbr-10m.mp3"
$FFMPEG $COMMON -f lavfi -i "sine=frequency=110:sample_rate=16000:duration=7200" -ac 1 -c:a libmp3lame -q:a 9 -metadata title="Synthetic two hour seek fixture" "$OUT/tone-vbr-2h.mp3"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -af atrim=start_sample=0:end_sample=44100 -c:a pcm_s16le "$OUT/boundary-01.wav"
$FFMPEG $COMMON -i "$OUT/tone-44k-stereo.wav" -af atrim=start_sample=44100:end_sample=88200 -c:a pcm_s16le "$OUT/boundary-02.wav"
$FFMPEG $COMMON -i "$OUT/boundary-01.wav" -c:a libmp3lame -q:a 2 -metadata track=1 "$OUT/boundary-01.mp3"
$FFMPEG $COMMON -i "$OUT/boundary-02.wav" -c:a libmp3lame -q:a 2 -metadata track=2 "$OUT/boundary-02.mp3"
for part in 01 02; do
  $FFMPEG $COMMON -i "$OUT/boundary-$part.wav" -c:a flac "$OUT/boundary-$part.flac"
  $FFMPEG $COMMON -i "$OUT/boundary-$part.wav" -c:a alac "$OUT/boundary-$part-alac.m4a"
  $FFMPEG $COMMON -i "$OUT/boundary-$part.wav" -c:a aac -b:a 160k "$OUT/boundary-$part-aac.m4a"
  $FFMPEG $COMMON -i "$OUT/boundary-$part.wav" -c:a libopus -b:a 128k "$OUT/boundary-$part.opus"
  $FFMPEG $COMMON -i "$OUT/boundary-$part.wav" -c:a vorbis -strict -2 -q:a 5 "$OUT/boundary-$part.ogg"
done
head -c 96 "$OUT/tone-vbr-id3v23.mp3" > "$OUT/truncated.mp3"
printf 'not an audio file\n' > "$OUT/corrupt.mp3"

# HE-AAC encoding is exposed by the native probe because FFmpeg's bundled AAC
# encoder cannot select this Apple AudioToolbox profile explicitly.
if [ -x "$ROOT/.build/debug/AudioProbe" ]; then
  "$ROOT/.build/debug/AudioProbe" encode-he-aac "$OUT/tone-44k-stereo.wav" "$OUT/tone-he-aac.m4a" >/dev/null
  "$ROOT/.build/debug/AudioProbe" encode-he-aac "$OUT/tone-44k-stereo.wav" "$OUT/tone-he-aac.aac" >/dev/null
  "$ROOT/.build/debug/AudioProbe" encode-he-aac "$OUT/boundary-01.wav" "$OUT/boundary-01-he.m4a" >/dev/null
  "$ROOT/.build/debug/AudioProbe" encode-he-aac "$OUT/boundary-02.wav" "$OUT/boundary-02-he.m4a" >/dev/null
fi

cat > "$OUT/manifest.json" <<'JSON'
{
  "provenance": "Generated from FFmpeg's sine filter; no third-party recording is included.",
  "sampleRate": 44100,
  "sourceDurationSeconds": 2,
  "fixtures": [
    {"path":"tone-44k-stereo.wav","codec":"PCM s16","container":"WAVE","prototype":true},
    {"path":"tone-44k.flac","codec":"FLAC","container":"FLAC","prototype":true},
    {"path":"tone-aac.m4a","codec":"AAC-LC","container":"MPEG-4","prototype":true},
    {"path":"tone-aac-lc.aac","codec":"AAC-LC","container":"ADTS"},
    {"path":"tone-he-aac.m4a","codec":"HE-AAC","container":"MPEG-4","generator":"AudioProbe encode-he-aac"},
    {"path":"tone-he-aac.aac","codec":"HE-AAC","container":"ADTS","generator":"AudioProbe encode-he-aac"},
    {"path":"tone-alac-16.m4a","codec":"ALAC 16-bit","container":"MPEG-4"},
    {"path":"tone-alac-24.m4a","codec":"ALAC 24-bit","container":"MPEG-4"},
    {"path":"tone-flac-96k-24.flac","codec":"FLAC 24-bit","container":"FLAC","sampleRate":96000},
    {"path":"tone-flac-192k-24.flac","codec":"FLAC 24-bit","container":"FLAC","sampleRate":192000},
    {"path":"tone-float32.wav","codec":"PCM float32","container":"WAVE"},
    {"path":"tone-aiff-24.aiff","codec":"PCM 24-bit","container":"AIFF"},
    {"path":"tone-vorbis.ogg","codec":"Vorbis","container":"Ogg"},
    {"path":"tone-opus.opus","codec":"Opus","container":"Ogg"},
    {"path":"chained-opus.opus","codec":"Opus chained stream","container":"Ogg","expected":"policy-dependent"},
    {"path":"multichannel-5_1.flac","codec":"FLAC","container":"FLAC","channels":6,"expected":"unsupported"},
    {"path":"silence-bookends.flac","codec":"FLAC","container":"FLAC","expectedDecodedFrames":66150,"purpose":"preserve source silence"},
    {"path":"truncated.mp3","codec":"MP3","container":"MPEG audio","expected":"corrupt"},
    {"path":"corrupt.mp3","expected":"corrupt"},
    {"path":"tone-vbr-id3v23.mp3","codec":"MP3 VBR","container":"MPEG audio","prototype":true},
    {"path":"tone-cbr-id3v24.mp3","codec":"MP3 CBR","container":"MPEG audio","prototype":true},
    {"path":"tone-vbr-10m.mp3","codec":"MP3 VBR","container":"MPEG audio","durationSeconds":600,"purpose":"bounded long-file seek"},
    {"path":"tone-vbr-2h.mp3","codec":"MP3 VBR","container":"MPEG audio","durationSeconds":7200,"purpose":"two-hour bounded seek"},
    {"path":"boundary-01.wav","codec":"PCM s16","container":"WAVE","expectedDecodedFrames":44100},
    {"path":"boundary-02.wav","codec":"PCM s16","container":"WAVE","expectedDecodedFrames":44100},
    {"path":"boundary-01.mp3","codec":"MP3 VBR","container":"MPEG audio","expectedDecodedFrames":44100,"trimming":"LAME/Xing metadata"},
    {"path":"boundary-02.mp3","codec":"MP3 VBR","container":"MPEG audio","expectedDecodedFrames":44100,"trimming":"LAME/Xing metadata"}
    ,{"path":"boundary-01.flac + boundary-02.flac","codec":"FLAC","purpose":"gapless boundary"}
    ,{"path":"boundary-01-alac.m4a + boundary-02-alac.m4a","codec":"ALAC","purpose":"gapless boundary"}
    ,{"path":"boundary-01-aac.m4a + boundary-02-aac.m4a","codec":"AAC-LC","purpose":"gapless boundary"}
    ,{"path":"boundary-01-he.m4a + boundary-02-he.m4a","codec":"HE-AAC","purpose":"gapless boundary"}
    ,{"path":"boundary-01.opus + boundary-02.opus","codec":"Opus","purpose":"gapless boundary"}
    ,{"path":"boundary-01.ogg + boundary-02.ogg","codec":"Vorbis","purpose":"document encoder padding limit"}
  ]
}
JSON

echo "Generated fixtures in $OUT"
