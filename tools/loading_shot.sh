#!/usr/bin/env bash
# The loading screen's picture, put where `PlayLoading` draws it from.
#
#   tools/loading_shot.sh <picture.png>    use a picture you took (P in a session writes
#                                          artifacts/human/play-<stamp>-<n>.png)
#   tools/loading_shot.sh                  take one with the `loading_shot` gate instead
#
# The picture is a render of community content and is not committed: assets/ui/ is gitignored
# but for the note that says so, and a checkout without the picture shows a gradient instead.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ge 1 ]]; then
    png="$1"
else
    "$REPO_ROOT/tools/gate.sh" loading_shot | grep -E 'HARNESS_GATE_RESULT|loading_shot ' | cut -c1-400
    png="$REPO_ROOT/artifacts/loading_shot/hero_3q.png"
fi
[[ -f "$png" ]] || { echo "loading_shot.sh: no picture at $png" >&2; exit 1; }
mkdir -p "$REPO_ROOT/assets/ui"
cp "$png" "$REPO_ROOT/assets/ui/loading.png"
echo "loading_shot.sh: $png -> assets/ui/loading.png"
