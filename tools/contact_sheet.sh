#!/usr/bin/env bash
# Turns a recorded movie into still images a reader can inspect in one look.
#
#   tools/contact_sheet.sh <movie.avi> [tiles_wide] [tiles_high]
#
# Produces two sheets next to the movie:
#   *-sheet.png   evenly spaced frames, tiled. Shows what happened.
#   *-diff.png    consecutive-frame differences, tiled. Shows what moved, which is how
#                 ghosting, smear and particle boiling become visible in a still image
#                 instead of being argued about.
set -euo pipefail

MOVIE="${1:?usage: contact_sheet.sh <movie.avi> [tiles_wide] [tiles_high]}"
COLS="${2:-4}"
ROWS="${3:-3}"
TILE_WIDTH="${TILE_WIDTH:-480}"

[[ -f "$MOVIE" ]] || { echo "contact_sheet.sh: no such movie: $MOVIE" >&2; exit 2; }
command -v ffmpeg >/dev/null || { echo "contact_sheet.sh: ffmpeg not installed" >&2; exit 2; }

base="${MOVIE%.*}"
frames="$(ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames -of csv=p=0 "$MOVIE" | tr -d '\r,')"
tiles=$((COLS * ROWS))
step=$(( frames > tiles ? frames / tiles : 1 ))

ffmpeg -y -loglevel error -i "$MOVIE" \
    -vf "select=not(mod(n\,${step})),scale=${TILE_WIDTH}:-1,tile=${COLS}x${ROWS}" \
    -frames:v 1 "${base}-sheet.png"

# tblend=difference lights up only what changed between neighbouring frames.
ffmpeg -y -loglevel error -i "$MOVIE" \
    -vf "tblend=all_mode=difference,select=not(mod(n\,${step})),scale=${TILE_WIDTH}:-1,tile=${COLS}x${ROWS}" \
    -frames:v 1 "${base}-diff.png"

echo "contact_sheet.sh: ${frames} frames -> ${base}-sheet.png and ${base}-diff.png"
