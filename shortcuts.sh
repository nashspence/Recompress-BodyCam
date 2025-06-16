#!/usr/bin/env zsh
set -eux

# Prevent macOS from sleeping while this script runs
caffeinate -dimsu -w $$ &

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Set KEEP_ORIGINALS=1 to preserve source files
KEEP_ORIGINALS="${KEEP_ORIGINALS:-0}"
# Set DISABLE_UI=1 in CI environments to skip osascript calls
DISABLE_UI="${DISABLE_UI:-0}"

notify() {
  [[ "$DISABLE_UI" == "1" ]] && return
  osascript -e "display notification \"$*\" with title \"BodyCam Re-encode\""
}

# Return the creation timestamp of a file as seconds since epoch. Prefer the
# embedded `creation_time` metadata and fall back to the filesystem timestamp.
creation_epoch_for() {
  local f="$1"
  local meta
  meta=$(ffprobe -v quiet -show_entries format_tags=creation_time -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null | head -n 1 || true)
  if [[ -n "$meta" ]]; then
    meta="${meta%Z}"
    meta="${meta%.*}"
    if date -j -f "%Y-%m-%dT%H:%M:%S%z" "$meta" +%s 2>/dev/null; then
      return
    fi
  fi
  stat -f %B "$f"
}

out_root="${1:-}"
if [[ -z "$out_root" || ! -d "$out_root" ]]; then
  out_root=$(osascript -e 'POSIX path of (choose folder with prompt "Select output directory for re-encoded clips")')
else
  shift
fi

FILES=( "$@" )
if (( ${#FILES[@]} == 0 )); then
  notify "No bodycam files selected → exiting"
  echo "❌ No input files. Exiting." >&2
  exit 1
fi

# ───────────────────────────────────────────────────────────────────────────────
# Setup logging in the chosen output directory. Each clip will be placed in a
# subfolder based on its individual creation time.

LOGFILE="$out_root/BodyCam-Reencode-$(date +'%Y%m%dT%H%M%S').log"
touch "$LOGFILE" 2>/dev/null || { echo "❌ Cannot write to log file '$LOGFILE'." >&2; exit 1; }
exec 2>>"$LOGFILE"
if [[ "$DISABLE_UI" != "1" ]]; then
  osascript -e "tell application \"Terminal\" to do script \"tail -f '$LOGFILE'\""
fi
echo "▶ Script started at $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >&2
trap 'ret=$?; echo "▶ Script exited with code $ret at $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >&2' EXIT
# ───────────────────────────────────────────────────────────────────────────────

cd -- "$(dirname -- "${FILES[1]}")"
echo "CWD is now: $PWD" >&2

echo "▶ Re-encoding ${#FILES[@]} clip(s) to AV1 (libsvtav1) + Opus…" >&1
notify "Re-encoding ${#FILES[@]} clips…"

index=1
for file_i in "${FILES[@]}"; do
  creation_epoch=$(creation_epoch_for "$file_i")
  datepart=$(date -r "$creation_epoch" +"%Y%m%d")
  target_dir="$out_root/$datepart"
  mkdir -p "$target_dir"
  base_name="${file_i##*/}"
  base_name="${base_name%.*}"
  outname="${base_name}_av1.mp4"
  outpath="$target_dir/$outname"

  echo "[$index/${#FILES[@]}] '$file_i' → '$outpath'" >&1
  ffmpeg -hide_banner -loglevel warning -stats -y \
    -i "$file_i" \
    -map 0:v:0 -map 0:a:0 \
    -c:v libsvtav1 -crf 42 -preset 5 \
    -c:a libopus \
      -b:a 28k -vbr on \
      -compression_level 10 -application audio \
      -frame_duration 40 -ar 24000 -ac 1 -cutoff 12000 \
    -c:s copy -c:d copy \
    "$outpath"
  [[ -f "$outpath" ]] || { echo "❌ Error: transcoded file '$outpath' not found." >&2; exit 1; }

  # Delete the original file once the encode is confirmed unless KEEP_ORIGINALS=1
  if [[ "$KEEP_ORIGINALS" != "1" ]]; then
    rm "$file_i" || echo "⚠️ Could not delete original '$file_i'." >&2
  fi

  (( index++ ))
done

echo "" >&1
echo "▶ Transcoding complete. Generated files:" >&1
find "$out_root" -name '*_av1.mp4' -print | sed 's/^/    /'
echo "" >&1

if [[ "$KEEP_ORIGINALS" == "1" ]]; then
  notify "Original files preserved; re-encoded clips are in subfolders"
else
  notify "Deleted original files; re-encoded clips are in subfolders"
fi
echo "--------------------------------------" >>"$LOGFILE"
echo "Completed successfully at $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >>"$LOGFILE"
echo "Log file is: $LOGFILE" >>"$LOGFILE"
echo "--------------------------------------" >>"$LOGFILE"
