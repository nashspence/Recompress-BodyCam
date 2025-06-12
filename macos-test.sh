#!/usr/bin/env bash
set -euo pipefail

# Integration test for the "Recompress BodyCam" Quick Action.
# Requires macOS with zsh, ffmpeg and (optionally) the Shortcuts CLI.

tmpdir=$(mktemp -d)
outdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir" "$outdir"; }
trap cleanup EXIT

# Generate two 1‑second sample clips with different metadata
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -metadata creation_time="2024-01-01T12:00:00Z" -c:v libx264 -t 1 "$tmpdir/in1.mov" -y >/dev/null 2>&1
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -metadata creation_time="2024-01-02T12:00:00Z" -c:v libx264 -t 1 "$tmpdir/in2.mov" -y >/dev/null 2>&1

# Run the script directly with the output directory
zsh shortcuts.sh "$outdir" "$tmpdir/in1.mov" "$tmpdir/in2.mov"

# Verify that an output clip was produced
found1="$outdir/20240101/in1_av1.mp4"
found2="$outdir/20240102/in2_av1.mp4"
if [[ -f "$found1" && -f "$found2" ]]; then
  echo "✅ Both output files created"
else
  echo "❌ Output files not found" >&2
  exit 1
fi

# Check that a log file exists in the output root directory
logfile=$(find "$outdir" -maxdepth 1 -name '*.log' | head -n 1 || true)
if [[ -f "$logfile" ]]; then
  echo "✅ Log file created at $logfile"
else
  echo "❌ Log file not found" >&2
  exit 1
fi

