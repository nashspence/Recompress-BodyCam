#!/usr/bin/env zsh
set -eux

# Prevent macOS from sleeping while this script runs
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu -w $$ &
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Detect low-motion segments using ffmpeg's scene score. Both the SAD threshold
# and minimum segment length can be configured via `LOW_MOTION_SAD` and
# `LOW_MOTION_MIN_LEN` environment variables.
detect_low_motion() {
  local input="$1" tmp duration
  local sad_thresh="${LOW_MOTION_SAD:-0.003}"
  local min_len="${LOW_MOTION_MIN_LEN:-20}"
  tmp=$(mktemp)
  ffmpeg -hide_banner -loglevel info -i "$input" \
    -vf "select='lt(scene,${sad_thresh})',metadata=print:file=$tmp" \
    -vsync 0 -an -f null - >/dev/null 2>&1 || true
  duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input")
  awk -v dur="$duration" -v min_len="$min_len" '
    {
      if (match($0, /pts_time:([0-9.]+)/, m)) {
        t=m[1]
        if (start=="") start=t
        if (prev!="" && t-prev>1) {
          if (prev-start>=min_len) print start":"prev
          start=t
        }
        prev=t
        last=t
      }
    }
    END {
      if (prev!="" && last-start>=min_len) {
        end = (last<dur ? last : dur)
        print start":"end
      }
    }
  ' "$tmp"
  rm -f "$tmp"
}

# Convert an epoch timestamp to an ISO 8601 string in UTC.
iso_utc() {
  date -u -r "$1" +"%Y-%m-%dT%H:%M:%SZ"
}

# Encode a file while splitting low-motion segments into audio-only files. Any
# span of minimal movement lasting at least `LOW_MOTION_MIN_LEN` seconds becomes
# its own `.m4a` file with accurate `creation_time`. Video resumes in numbered
# parts with adjusted timestamps.
encode_with_low_motion() {
  local input="$1" output="$2" base_epoch="$3"
  local width height duration start end prev seg_idx low_idx part
  width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input")
  height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")
  duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input")
  local -a low_segments
  IFS=$'\n' low_segments=($(detect_low_motion "$input"))

  local base="${output%.*}" ext="${output##*.}"
  prev=0
  seg_idx=1
  low_idx=1

  if (( ${#low_segments[@]} == 0 )); then
    ffmpeg -hide_banner -loglevel warning -stats -y \
      -i "$input" \
      -map 0:v:0 -map 0:a:0 \
      -c:v libsvtav1 -crf 42 -preset 5 \
      -c:a libopus -b:a 28k -vbr on \
        -compression_level 10 -application audio \
        -frame_duration 40 -ar 24000 -ac 1 -cutoff 12000 \
      -metadata creation_time="$(iso_utc "$base_epoch")" \
      -movflags use_metadata_tags \
      -c:s copy -c:d copy "$output"
    return
  fi

  for seg in "${low_segments[@]}"; do
    start=${seg%:*}
    end=${seg#*:}
    if (( $(echo "$start > $prev" | bc -l) )); then
      part="$output"
      [[ $seg_idx -gt 1 ]] && part="${base}_part${seg_idx}.${ext}"
      ffmpeg -hide_banner -loglevel warning -stats -y \
        -ss "$prev" -to "$start" -i "$input" \
        -map 0:v:0 -map 0:a:0 \
        -c:v libsvtav1 -crf 42 -preset 5 \
        -c:a libopus -b:a 28k -vbr on \
          -compression_level 10 -application audio \
          -frame_duration 40 -ar 24000 -ac 1 -cutoff 12000 \
        -metadata creation_time="$(iso_utc $(printf '%.0f' $(echo "$base_epoch + $prev" | bc -l)))" \
        -movflags use_metadata_tags \
        -c:s copy -c:d copy "$part"
      seg_idx=$((seg_idx+1))
    fi

    ffmpeg -hide_banner -loglevel warning -stats -y \
      -ss "$start" -to "$end" -i "$input" -vn \
      -c:a aac -b:a 32k \
      -metadata creation_time="$(iso_utc $(printf '%.0f' $(echo "$base_epoch + $start" | bc -l)))" \
      -movflags use_metadata_tags \
      "${base}_lowmotion${low_idx}.m4a"
    low_idx=$((low_idx+1))
    prev=$end
  done

  if (( $(echo "$prev < $duration" | bc -l) )); then
    part="$output"
    [[ $seg_idx -gt 1 ]] && part="${base}_part${seg_idx}.${ext}"
    ffmpeg -hide_banner -loglevel warning -stats -y \
      -ss "$prev" -to "$duration" -i "$input" \
      -map 0:v:0 -map 0:a:0 \
      -c:v libsvtav1 -crf 42 -preset 5 \
      -c:a libopus -b:a 28k -vbr on \
        -compression_level 10 -application audio \
        -frame_duration 40 -ar 24000 -ac 1 -cutoff 12000 \
      -metadata creation_time="$(iso_utc $(printf '%.0f' $(echo "$base_epoch + $prev" | bc -l)))" \
      -movflags use_metadata_tags \
      -c:s copy -c:d copy "$part"
  fi
}

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
    # Remove fractional seconds and normalize timezone offsets for BSD date
    meta=$(echo "$meta" | \
      sed -E 's/\.[0-9]+(Z|[+-][0-9:]+)$/\1/' | \
      sed -E 's/Z$/+0000/' | \
      sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
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
  encode_with_low_motion "$file_i" "$outpath" "$creation_epoch"
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
