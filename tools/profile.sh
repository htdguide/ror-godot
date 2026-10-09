#!/usr/bin/env bash
# Which build this checkout is, for the shell tools: prints `dev` or `prod`, and the content
# roots that go with it. The same rule as game/config/build_profile.gd: an untracked
# profile.cfg at the repository root saying `profile=prod` under [build], otherwise dev.
#
#   tools/profile.sh            dev | prod
#   tools/profile.sh mods       the vehicles folder, relative to the root
#   tools/profile.sh maps       the maps folder, relative to the root
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="dev"
if [[ -f "$REPO_ROOT/profile.cfg" ]]; then
    stated="$(sed -n 's/^[[:space:]]*profile[[:space:]]*=[[:space:]]*"\{0,1\}\([A-Za-z]*\)"\{0,1\}.*$/\1/p' "$REPO_ROOT/profile.cfg" | head -1 | tr '[:upper:]' '[:lower:]')"
    [[ "$stated" == "prod" ]] && profile="prod"
fi
case "${1:-}" in
    "") echo "$profile" ;;
    mods) [[ "$profile" == "prod" ]] && echo "mods" || echo "assets/mods" ;;
    maps) [[ "$profile" == "prod" ]] && echo "maps" || echo "assets/terrains" ;;
    *) echo "usage: profile.sh [mods|maps]" >&2; exit 2 ;;
esac
