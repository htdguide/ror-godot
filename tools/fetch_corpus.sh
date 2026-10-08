#!/usr/bin/env bash
# Fetches archive mods for the `mod_corpus` gate, through the same portal Rigs of Rods' own
# in-game repository uses.
#
#   tools/fetch_corpus.sh [count] [categories]
#
# Lists the archive at https://v2.api.rigsofrods.org (the `remote_query_url` upstream ships),
# takes the `count` most-downloaded resources in the given categories (default 200 across
# 2 Trucks, 3 Cars, 4 Trailers, 5 Air & Sea, 6 Trains), downloads the first .zip of each from the
# forum exactly as the client does, and unpacks it under assets/corpus/<id>_<slug>/ beside a
# CORPUS.json saying where it came from, who wrote it and what licence it states.
#
# Resumable: a resource already unpacked is skipped. Nothing here is committed — the archive's
# mods carry varied and mostly unstated licences (PLAN §0.5) — and the corpus root is not one the
# vehicle library scans, so the suite's own runtime does not grow with it; only `mod_corpus` reads
# it.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNT="${1:-200}"
CATEGORIES="${2:-2,3,4,5,6}"
PORTAL="https://v2.api.rigsofrods.org"
FORUM="https://forum.rigsofrods.org"
AGENT="Rigs of Rods Client/2024.x (ror-godot corpus fetch)"
CORPUS="$REPO_ROOT/assets/corpus"
ZIPS="$CORPUS/_zips"
MAX_FILE_BYTES=$((200 * 1024 * 1024))
mkdir -p "$ZIPS"
# Godot must not import ten gigabytes of somebody else's textures, and `asset_licenses` reads the
# marker as "fetched locally, not shipped" — the same standing as assets/mods and assets/terrains.
touch "$CORPUS/.gdignore"

listing="$(mktemp)"
curl -s -m 120 -A "$AGENT" "$PORTAL/resources" > "$listing" || { echo "fetch_corpus: the portal did not answer" >&2; exit 1; }
plan="$(mktemp)"
python3 - "$listing" "$COUNT" "$CATEGORIES" > "$plan" <<'PY'
import json, re, sys
rows = json.load(open(sys.argv[1]))["resources"]
wanted = {int(c) for c in sys.argv[3].split(",")}
rows = [r for r in rows if r.get("can_download") and r["resource_category_id"] in wanted]
rows.sort(key=lambda r: -r["download_count"])
for r in rows[: int(sys.argv[2])]:
    slug = re.sub(r"[^a-z0-9]+", "-", r["title"].lower()).strip("-")[:48]
    print("%d\t%s\t%s" % (r["resource_id"], slug, json.dumps(r)))
PY
total=$(wc -l < "$plan" | tr -d ' ')
echo "fetch_corpus: $total resources planned"
done_n=0; skipped=0; failed=0
while IFS=$'\t' read -r id slug row; do
    dir="$CORPUS/${id}_${slug}"
    if [[ -f "$dir/CORPUS.json" ]]; then
        skipped=$((skipped + 1)); continue
    fi
    files="$(curl -s -m 60 -A "$AGENT" "$PORTAL/resources/$id")"
    pick="$(python3 -c '
import json, sys
d = json.loads(sys.argv[1]).get("resource", {})
for f in d.get("current_files") or []:
    if f["filename"].lower().endswith(".zip") and f["size"] <= int(sys.argv[2]):
        print("%d\t%s\t%d" % (f["id"], f["filename"], f["size"])); break
' "$files" "$MAX_FILE_BYTES" 2>/dev/null)"
    if [[ -z "$pick" ]]; then
        echo "  $id $slug: no zip under the size cap"; failed=$((failed + 1)); continue
    fi
    IFS=$'\t' read -r fid fname fsize <<< "$pick"
    zip="$ZIPS/${id}_${fname}"
    if [[ ! -s "$zip" ]]; then
        code="$(curl -s -m 900 -L -A "$AGENT" -o "$zip.part" -w '%{http_code}' "$FORUM/resources/$id/download?file=$fid")"
        if [[ "$code" != "200" ]]; then
            echo "  $id $slug: download returned $code"; rm -f "$zip.part"; failed=$((failed + 1)); continue
        fi
        mv "$zip.part" "$zip"
    fi
    mkdir -p "$dir"
    if ! unzip -q -o "$zip" -d "$dir" 2>/dev/null; then
        echo "  $id $slug: $fname did not unzip"; rm -rf "$dir"; failed=$((failed + 1)); continue
    fi
    python3 - "$dir/CORPUS.json" "$row" "$fid" "$fname" "$fsize" <<'PY'
import json, sys, time
r = json.loads(sys.argv[2])
json.dump({
    "resource_id": r["resource_id"], "title": r["title"], "category": r["resource_category_id"],
    "authors": r.get("custom_fields", {}).get("authors", ""),
    "license": r.get("custom_fields", {}).get("license", ""),
    "view_url": r["view_url"], "file_id": int(sys.argv[3]), "file": sys.argv[4],
    "bytes": int(sys.argv[5]), "download_count": r["download_count"],
    "fetched": time.strftime("%Y-%m-%d"),
}, open(sys.argv[1], "w"), indent=2)
PY
    done_n=$((done_n + 1))
    echo "  $done_n/$total  $id $slug  ($fname, $((fsize / 1024)) KB)"
done < "$plan"
rm -f "$listing" "$plan"
echo "fetch_corpus: $done_n fetched, $skipped already here, $failed failed; corpus at $CORPUS"
