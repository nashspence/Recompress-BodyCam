#!/usr/bin/env zsh
set -eux

LOGFILE="/Users/nashspence/Desktop/BodyCam-Reencode-$(date +'%Y%m%dT%H%M%S').log"
touch "$LOGFILE" 2>/dev/null || { echo "❌ Cannot write to log file '$LOGFILE'." >&2; exit 1; }
exec 2>>"$LOGFILE"
osascript -e "tell application \"Terminal\" to do script \"tail -f '$LOGFILE'\""
echo "▶ Script started at $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >&2
trap 'ret=$?; echo "▶ Script exited with code $ret at $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >&2' EXIT
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

notify() {
  osascript -e "display notification \"$*\" with title \"BodyCam Re-encode\""
}

FILES=( "$@" )
if (( ${#FILES[@]} == 0 )); then
  notify "No bodycam files selected → exiting"
  echo "❌ No input files. Exiting." >&2
  exit 1
fi

# ───────────────────────────────────────────────────────────────────────────────
# Instead of extracting “datepart” from the filename, get the filesystem creation date
# of the first selected file (e.g. 2025-06-03 → “2025_0603”).
firstfile="${FILES[1]}"

# Use stat to fetch the file’s creation timestamp (in seconds since epoch)
creation_epoch=$(stat -f %B "$firstfile")

# Format that timestamp as YYYY_MMDD (same pattern as “2025_0603”)
datepart=$(date -r "$creation_epoch" +"%Y_%m%d")

target_dir="/Volumes/Sabrent Rocket XTRM-Q 2TB/bodycam/$datepart"

# Create the directory if it doesn't already exist
mkdir -p "$target_dir"
echo "▶ Created (or verified) directory: $target_dir" >&2
# ───────────────────────────────────────────────────────────────────────────────

cd -- "$(dirname -- "${FILES[1]}")"
echo "CWD is now: $PWD" >&2

echo "▶ Re-encoding ${#FILES[@]} clip(s) to AV1 (libsvtav1) + Opus…" >&1
notify "Re-encoding ${#FILES[@]} clips…"

index=1
for file_i in "${FILES[@]}"; do
  base_name="${file_i##*/}"
  base_name="${base_name%.*}"
  outname="${base_name}_recompressed_av1.mp4"
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

  # Delete the original file once the encode is confirmed
  rm "$file_i" || echo "⚠️ Could not delete original '$file_i'." >&2

  (( index++ ))
done

echo "" >&1
echo "▶ Transcoding complete. Generated files in $target_dir:" >&1
printf "    %s\n" "$target_dir"/*_recompressed_av1.mp4 >&1
echo "" >&1

notify "Deleted original files; re-encoded clips are in $datepart"
echo "--------------------------------------" >>"$LOGFILE"
echo "Completed successfully at $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >>"$LOGFILE"
echo "Log file is: $LOGFILE" >>"$LOGFILE"
echo "--------------------------------------" >>"$LOGFILE"
