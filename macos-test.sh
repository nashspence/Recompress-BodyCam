#!/usr/bin/env bash
set -euo pipefail

# Integration test for the "Recompress BodyCam" Quick Action.
# Requires macOS with zsh, ffmpeg and (optionally) the Shortcuts CLI.

tmpdir=$(mktemp -d)
outdir_keep=$(mktemp -d)
outdir_del=$(mktemp -d)
cleanup() { rm -rf "$tmpdir" "$outdir_keep" "$outdir_del"; }
trap cleanup EXIT

# Generate two 1‑second sample clips with different metadata
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -f lavfi -i sine=frequency=440:duration=1 \
  -metadata creation_time="2024-01-01T12:00:00Z" -c:v libx264 -c:a aac -shortest \
  "$tmpdir/in1.mov" -y >/dev/null 2>&1
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -f lavfi -i sine=frequency=440:duration=1 \
  -metadata creation_time="2024-01-02T12:00:00Z" -c:v libx264 -c:a aac -shortest \
  "$tmpdir/in2.mov" -y >/dev/null 2>&1

# Run the script directly with the output directory. If the command fails, dump
# any generated log file to help diagnose the issue.
KEEP_ORIGINALS=1 zsh shortcuts.sh "$outdir_keep" "$tmpdir/in1.mov" "$tmpdir/in2.mov" || {
  echo "❌ shortcuts.sh failed during KEEP_ORIGINALS run" >&2
  log=$(find "$outdir_keep" -maxdepth 1 -name '*.log' | head -n 1 || true)
  [[ -f "$log" ]] && { echo "----- Log from KEEP_ORIGINALS run -----"; cat "$log"; echo "---------------------------------------"; }
  exit 1
}
if [[ -f "$tmpdir/in1.mov" && -f "$tmpdir/in2.mov" ]]; then
  echo "✅ Originals preserved after KEEP_ORIGINALS run"
else
  echo "❌ Originals missing after KEEP_ORIGINALS run" >&2
  exit 1
fi
zsh shortcuts.sh "$outdir_del" "$tmpdir/in1.mov" "$tmpdir/in2.mov" || {
  echo "❌ shortcuts.sh failed during deletion run" >&2
  log=$(find "$outdir_del" -maxdepth 1 -name '*.log' | head -n 1 || true)
  [[ -f "$log" ]] && { echo "----- Log from deletion run -----"; cat "$log"; echo "--------------------------------"; }
  exit 1
}

# Verify that an output clip was produced
found1k="$outdir_keep/20240101/in1_av1.mp4"
found2k="$outdir_keep/20240102/in2_av1.mp4"
found1d="$outdir_del/20240101/in1_av1.mp4"
found2d="$outdir_del/20240102/in2_av1.mp4"
if [[ -f "$found1k" && -f "$found2k" && -f "$found1d" && -f "$found2d" ]]; then
  echo "✅ Both runs produced output files"
else
  echo "❌ Output files not found" >&2
  exit 1
fi

# Check that a log file exists in the output root directory
logk=$(find "$outdir_keep" -maxdepth 1 -name '*.log' | head -n 1 || true)
logd=$(find "$outdir_del" -maxdepth 1 -name '*.log' | head -n 1 || true)
if [[ -f "$logk" && -f "$logd" ]]; then
  echo "✅ Log files created"
else
  echo "❌ Log file not found" >&2
  exit 1
fi

# Originals should be removed after the second run
if [[ ! -f "$tmpdir/in1.mov" && ! -f "$tmpdir/in2.mov" ]]; then
  echo "✅ Originals removed after deletion run"
else
  echo "❌ Originals not removed" >&2
  exit 1
fi

