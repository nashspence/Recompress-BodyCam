#!/usr/bin/env bash
set -euo pipefail

# Integration test for shortcuts.sh on non-macOS systems.

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir=$(mktemp -d)
outdir_keep=$(mktemp -d)
outdir_del=$(mktemp -d)
mockbin=$(mktemp -d)
cleanup() { rm -rf "$tmpdir" "$outdir_keep" "$outdir_del" "$mockbin"; }
trap cleanup EXIT

# ---------------------------------------------------------------------
# Create stub utilities that exist on macOS only
# ---------------------------------------------------------------------
cat >"$mockbin/caffeinate" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "$mockbin/caffeinate"

cat >"$mockbin/osascript" <<'EOS'
#!/usr/bin/env bash
# Provide minimal behaviour for notifications and choose folder dialogs
if [[ "$1" == "-e" ]]; then
  if grep -q 'POSIX path of (choose folder' <<<"$2"; then
    echo "/tmp"
  fi
  exit 0
fi
exit 0
EOS
chmod +x "$mockbin/osascript"

cat >"$mockbin/stat" <<'EOS'
#!/usr/bin/env bash
if [[ "$1" == "-f" && "$2" == "%B" ]]; then
  shift 2
  /usr/bin/stat -c %Y "$1"
else
  /usr/bin/stat "$@"
fi
EOS
chmod +x "$mockbin/stat"

cat >"$mockbin/date" <<'EOS'
#!/usr/bin/env bash
# Emulate BSD date flags used by shortcuts.sh
if [[ "$1" == "-j" && "$2" == "-f" ]]; then
  shift 2
  format="$1"; shift
  value="$1"; shift
  value="${value%Z}"
  value="${value%.*}"
  /usr/bin/date -d "$value" +%s
elif [[ "$1" == "-r" ]]; then
  shift
  sec="$1"; shift
  /usr/bin/date -d "@$sec" "$@"
else
  /usr/bin/date "$@"
fi
EOS
chmod +x "$mockbin/date"

export PATH="$mockbin:$PATH"

# ---------------------------------------------------------------------
# Generate sample videos with metadata and audio
# ---------------------------------------------------------------------
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -f lavfi -i sine=frequency=440:duration=1 -metadata creation_time="2024-01-01T12:00:00Z" -c:v libx264 -c:a aac -shortest "$tmpdir/in1.mov" -y >/dev/null 2>&1
ffmpeg -f lavfi -i testsrc=size=320x240:duration=1 -f lavfi -i sine=frequency=440:duration=1 -metadata creation_time="2024-01-02T12:00:00Z" -c:v libx264 -c:a aac -shortest "$tmpdir/in2.mov" -y >/dev/null 2>&1

# ---------------------------------------------------------------------
# Run once preserving originals
# ---------------------------------------------------------------------
(cd "$root_dir" && KEEP_ORIGINALS=1 zsh shortcuts.sh "$outdir_keep" "$tmpdir/in1.mov" "$tmpdir/in2.mov")

# Run again with default deletion behaviour
# ---------------------------------------------------------------------
(cd "$root_dir" && zsh shortcuts.sh "$outdir_del" "$tmpdir/in1.mov" "$tmpdir/in2.mov")

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
