#!/usr/bin/env bash
# Browses the visual history that gate runs leave behind.
#
#   tools/history.sh list                     what has been archived, newest first
#   tools/history.sh shots <path/to/shot.png> every version of one capture, oldest first
#   tools/history.sh sheet <path/to/shot.png> those versions as one contact sheet
#
# The path is the capture's path inside a run, for example vehicle/hero_3q.png.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HISTORY="$REPO_ROOT/history"

[[ -d "$HISTORY" ]] || { echo "no history yet: run tools/gate.sh first" >&2; exit 0; }

case "${1:-list}" in
    list)
        printf '%-28s %s\n' RUN CAPTURES
        for run in $(ls -1 "$HISTORY" | sort -r); do
            printf '%-28s %s\n' "$run" "$(find "$HISTORY/$run" -name '*.png' | wc -l | tr -d ' ')"
        done
        ;;
    shots)
        shot="${2:?usage: history.sh shots <path/to/shot.png>}"
        for run in $(ls -1 "$HISTORY" | sort); do
            [[ -f "$HISTORY/$run/$shot" ]] && echo "$HISTORY/$run/$shot"
        done
        ;;
    sheet)
        shot="${2:?usage: history.sh sheet <path/to/shot.png>}"
        command -v ffmpeg >/dev/null || { echo "history.sh: ffmpeg not installed" >&2; exit 2; }
        list="$(mktemp)"
        count=0
        for run in $(ls -1 "$HISTORY" | sort); do
            if [[ -f "$HISTORY/$run/$shot" ]]; then
                printf "file '%s'\n" "$HISTORY/$run/$shot" >> "$list"
                count=$((count + 1))
            fi
        done
        [[ $count -eq 0 ]] && { echo "history.sh: no archived copies of $shot" >&2; exit 1; }
        out="$REPO_ROOT/artifacts/history-$(basename "${shot%.png}")-sheet.png"
        mkdir -p "$(dirname "$out")"
        cols=4
        rows=$(( (count + cols - 1) / cols ))
        ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" \
            -vf "scale=480:-1,tile=${cols}x${rows}" -frames:v 1 "$out"
        rm -f "$list"
        echo "history.sh: $count versions of $shot -> $out"
        ;;
    *)
        echo "usage: history.sh [list|shots|sheet]" >&2
        exit 2
        ;;
esac
