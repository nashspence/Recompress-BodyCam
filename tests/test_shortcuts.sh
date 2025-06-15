#!/usr/bin/env bash
set -euo pipefail

# Integration test for shortcuts.sh on non-macOS systems.

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir=$(mktemp -d)
outdir=$(mktemp -d)
mockbin=$(mktemp -d)
cleanup() { rm -rf "$tmpdir" "$outdir" "$mockbin"; }
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
# Run the shortcut script with stubs
# ---------------------------------------------------------------------
(cd "$root_dir" && zsh shortcuts.sh "$outdir" "$tmpdir/in1.mov" "$tmpdir/in2.mov")

# ---------------------------------------------------------------------
# Verify output files were created in dated subfolders
# ---------------------------------------------------------------------
found1="$outdir/20240101/in1_av1.mp4"
found2="$outdir/20240102/in2_av1.mp4"
if [[ -f "$found1" && -f "$found2" ]]; then
  echo "✅ Output files created"
else
  echo "❌ Output files missing" >&2
  exit 1
fi

# Originals should have been deleted
if [[ ! -f "$tmpdir/in1.mov" && ! -f "$tmpdir/in2.mov" ]]; then
  echo "✅ Originals removed"
else
  echo "❌ Originals not removed" >&2
  exit 1
fi

# Log file should exist in output directory
logfile=$(find "$outdir" -maxdepth 1 -name '*.log' | head -n 1 || true)
if [[ -f "$logfile" ]]; then
  echo "✅ Log file created at $logfile"
else
  echo "❌ Log file not found" >&2
  exit 1
fi
