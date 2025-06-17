#!/usr/bin/env bash
# audio only for low motion
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir=$(mktemp -d)
outdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir" "$outdir"; }
trap cleanup EXIT

# Create video with a long low-motion section (>20s)
ffmpeg -f lavfi -i testsrc=size=320x240:rate=30:duration=1 -f lavfi -i color=black:size=320x240:duration=25 -f lavfi -i sine=frequency=440:duration=26 \
  -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0,format=yuv420p[v]" -map "[v]" -map 2:a \
  -metadata creation_time='2024-01-03T12:00:00Z' -c:v libx264 -c:a aac -shortest "$tmpdir/in.mov" -y >/dev/null 2>&1

 (cd "$root_dir" && DISABLE_UI=1 zsh shortcuts.sh "$outdir" "$tmpdir/in.mov")

audiofile=$(find "$outdir" -name '*lowmotion1.m4a' | head -n 1)
 videofile=$(find "$outdir" -name '*_av1.mp4' | head -n 1)
 audio_ct=$(ffprobe -v quiet -show_entries format_tags=creation_time -of csv=p=0 "$audiofile")
 video_ct=$(ffprobe -v quiet -show_entries format_tags=creation_time -of csv=p=0 "$videofile")
 if [[ -f "$audiofile" && "$audio_ct" == '2024-01-03T12:00:01Z' && "$video_ct" == '2024-01-03T12:00:00Z' ]]; then
   echo "✅ audio only for low motion"
 else
   echo "❌ low motion segment handling failed" >&2
   exit 1
 fi
