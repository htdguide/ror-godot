#!/usr/bin/env bash
# The production build: a second checkout of this repository on the `prod` branch, marked by an
# untracked profile.cfg, bundling no content at all. Vehicles go in its mods/ and maps in its
# maps/, put there by whoever runs it. Nothing reaches `prod` except by `merge`, on purpose.
#
#   tools/prod.sh setup           create ../ror-godot-prod on branch prod, mark it, build it
#   tools/prod.sh merge           bring main into prod (fast-forward where possible)
#   tools/prod.sh status          what prod is missing from main
#   tools/prod.sh play [args]     open the production window (tools/play.sh there)
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD_DIR="${PROD_DIR:-$(dirname "$REPO_ROOT")/ror-godot-prod}"
BRANCH="prod"

case "${1:-}" in
    setup)
        if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
            git -C "$REPO_ROOT" branch "$BRANCH" main || exit 1
        fi
        if [[ ! -d "$PROD_DIR" ]]; then
            git -C "$REPO_ROOT" worktree add "$PROD_DIR" "$BRANCH" || exit 1
        fi
        printf '[build]\nprofile="prod"\n' > "$PROD_DIR/profile.cfg"
        mkdir -p "$PROD_DIR/mods" "$PROD_DIR/maps"
        ( cd "$PROD_DIR" && git submodule update --init --recursive ) || exit 1
        echo "prod.sh: building the extension in $PROD_DIR"
        ( cd "$PROD_DIR/extension" && scons target=template_debug -j"$(sysctl -n hw.ncpu)" ) || exit 1
        echo "prod.sh: building Terrain3D in $PROD_DIR"
        ( cd "$PROD_DIR" && tools/build_terrain3d.sh ) || exit 1
        echo "prod.sh: $PROD_DIR is the production build ($(cd "$PROD_DIR" && tools/profile.sh))."
        echo "prod.sh: vehicles go in $PROD_DIR/mods/, maps in $PROD_DIR/maps/."
        ;;
    merge)
        [[ -d "$PROD_DIR" ]] || { echo "prod.sh: no production checkout at $PROD_DIR; run setup" >&2; exit 1; }
        ( cd "$PROD_DIR" && git merge --ff main ) || exit 1
        ( cd "$PROD_DIR/extension" && scons target=template_debug -j"$(sysctl -n hw.ncpu)" >/dev/null ) || exit 1
        echo "prod.sh: prod is at $(git -C "$PROD_DIR" rev-parse --short HEAD)"
        ;;
    status)
        [[ -d "$PROD_DIR" ]] || { echo "prod.sh: no production checkout at $PROD_DIR; run setup" >&2; exit 1; }
        echo "prod at $(git -C "$PROD_DIR" rev-parse --short HEAD), main at $(git -C "$REPO_ROOT" rev-parse --short main)"
        git -C "$REPO_ROOT" log --oneline "$BRANCH..main"
        ;;
    play)
        shift
        [[ -d "$PROD_DIR" ]] || { echo "prod.sh: no production checkout at $PROD_DIR; run setup" >&2; exit 1; }
        exec "$PROD_DIR/tools/play.sh" "$@"
        ;;
    *)
        sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
