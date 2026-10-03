#!/usr/bin/env bash
# Photographs every object a map places, from outside, and names the ones you can see through.
#
#   tools/mapcheck.sh                       Port Starling
#   tools/mapcheck.sh --map lapaz           another map
#   tools/mapcheck.sh --map all             every map in the library, each mesh once
#   tools/mapcheck.sh --object haus4.mesh   one object by name
#
# Run this against any map this project has not drawn before. A map is only as correct as the
# objects it happens to use, and the content is what differs between maps: the renderer that
# draws Port Starling correctly has not thereby been shown to draw anything else correctly.
#
# Each view is captured twice against two backgrounds, so what the object drew is separated from
# the stage exactly, and every surface is dressed so its back draws a primary colour. A surface
# that is nearest the camera and shows its back is a surface you are looking through. The stills
# are under artifacts/outside/<mesh>/<view>.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

args=()
for token in "$@"; do
    if [[ "$token" == "--map" ]]; then
        args+=("--terrain-dir")
    else
        args+=("$token")
    fi
done

"$REPO_ROOT/tools/gate.sh" an_object_is_not_a_hole_from_outside ${args[@]+"${args[@]}"} \
    | grep -E 'HARNESS_GATE_RESULT' \
    | python3 -c '
import json, sys
for line in sys.stdin:
    row = json.loads(line.split(" ", 1)[1])
    print(("PASS" if row["pass"] else "FAIL"), row["detail"])
'
