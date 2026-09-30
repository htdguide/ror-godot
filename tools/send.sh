#!/usr/bin/env bash
# Runs a command in the dev session that is already open, and prints what it answered.
#
#   tools/send.sh "gate run smoke"
#   tools/send.sh "gate all"
#   tools/send.sh "map list"
#
# This is the same drop box the agent uses and the same command table the console uses, so what
# you type here, what you type in the window, and what the agent runs are one set of commands.
#
# Needs a session open (tools/dev.sh). Without one there is nothing polling the drop box, and
# this says so rather than leaving a file to be run by surprise the next time one starts.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONSOLE="$REPO_ROOT/artifacts/console"
TIMEOUT_S="${TIMEOUT_S:-600}"

if [[ $# -lt 1 ]]; then
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
fi

if ! pgrep -f "Godot.*--path $REPO_ROOT" >/dev/null 2>&1; then
    echo "send.sh: no session is open. Start one with tools/dev.sh" >&2
    exit 3
fi

mkdir -p "$CONSOLE/in"
out="$CONSOLE/out.jsonl"
before=0
[[ -f "$out" ]] && before="$(wc -l < "$out" | tr -d ' ')"

# The name is the sequence the session runs them in, so a second send while the first is still
# running still happens in the order they were sent.
seq_file="$CONSOLE/in/$(date +%s%N).cmd"
printf '%s\n' "$1" > "$seq_file"

# The reply file does not exist until the first command of a session answers, so it is counted
# rather than read: `wc` on a missing file is an error three times a second.
lines_now() {
    [[ -f "$out" ]] && wc -l < "$out" | tr -d ' ' || echo 0
}

waited=0
while [[ "$(lines_now)" -le "$before" ]]; do
    sleep 0.2
    waited=$((waited + 1))
    if [[ $((waited / 5)) -ge "$TIMEOUT_S" ]]; then
        echo "send.sh: no reply in ${TIMEOUT_S}s. The session may be busy or gone." >&2
        exit 4
    fi
done

tail -n +$((before + 1)) "$out" | python3 -c '
import json, sys
for line in sys.stdin:
    row = json.loads(line)
    where = ("  -> " + row["artifact"]) if row.get("artifact") else ""
    print("%s  %.0fms  %s%s" % ("ok " if row["ok"] else "ERR", row["ms"], row["detail"], where))
    sys.exit(0 if row["ok"] else 1)
'
