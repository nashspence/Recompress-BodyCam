#!/usr/bin/env bash
set -euo pipefail

# Integration test for shortcuts.sh on non-macOS systems.

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir=$(mktemp -d)
outdir_keep=$(mktemp -d)
outdir_del=$(mktemp -d)
cleanup() { rm -rf "$tmpdir" "$outdir_keep" "$outdir_del"; }
trap cleanup EXIT

# ---------------------------------------------------------------------
# Generate sample videos with metadata and audio
# ---------------------------------------------------------------------
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -f lavfi -i sine=frequency=440:duration=1 -metadata creation_time="2024-01-01T12:00:00Z" -c:v libx264 -c:a aac -shortest "$tmpdir/in1.mov" -y >/dev/null 2>&1
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -f lavfi -i sine=frequency=440:duration=1 -metadata creation_time="2024-01-02T12:00:00Z" -c:v libx264 -c:a aac -shortest "$tmpdir/in2.mov" -y >/dev/null 2>&1

# ---------------------------------------------------------------------
# Run once preserving originals
# ---------------------------------------------------------------------
(cd "$root_dir" && KEEP_ORIGINALS=1 DISABLE_UI=1 zsh shortcuts.sh "$outdir_keep" "$tmpdir/in1.mov" "$tmpdir/in2.mov")

# Run again with default deletion behaviour
# ---------------------------------------------------------------------
(cd "$root_dir" && DISABLE_UI=1 zsh shortcuts.sh "$outdir_del" "$tmpdir/in1.mov" "$tmpdir/in2.mov")

# ---------------------------------------------------------------------
# Verify output files were created in dated subfolders
# ---------------------------------------------------------------------
found_keep1="$outdir_keep/20240101/in1_av1.mp4"
found_keep2="$outdir_keep/20240102/in2_av1.mp4"
found_del1="$outdir_del/20240101/in1_av1.mp4"
found_del2="$outdir_del/20240102/in2_av1.mp4"
if [[ -f "$found_keep1" && -f "$found_keep2" && -f "$found_del1" && -f "$found_del2" ]]; then
  echo "✅ Output files created"
else
  echo "❌ Output files missing" >&2
  exit 1
fi

# Originals should remain after first run and be deleted after second
if [[ ! -f "$tmpdir/in1.mov" && ! -f "$tmpdir/in2.mov" ]]; then
  echo "✅ Originals removed after second run"
else
  echo "❌ Originals not removed" >&2
  exit 1
fi

# Log file should exist in output directory
logfile_keep=$(find "$outdir_keep" -maxdepth 1 -name '*.log' | head -n 1 || true)
logfile_del=$(find "$outdir_del" -maxdepth 1 -name '*.log' | head -n 1 || true)
if [[ -f "$logfile_keep" && -f "$logfile_del" ]]; then
  echo "✅ Log files created"
else
  echo "❌ Log file not found" >&2
  exit 1
fi
