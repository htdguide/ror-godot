#!/usr/bin/env python3
"""Extracts named functions from the pinned Rigs of Rods checkout into one compilable file.

The point is that nothing is copied into this repository. The oracle is regenerated from
vendor/rigs-of-rods on every build, so it cannot quietly drift from the upstream it claims to
be. If a function is renamed, moved or reshaped upstream, extraction fails loudly rather than
comparing against a stale copy of something that no longer exists.

Usage: extract.py <upstream source root> <output .cpp>
"""

import sys
from pathlib import Path

# Each entry names a file under the upstream source root and the exact signature line the
# function begins with. Matching on the full signature rather than the bare name means an
# overload appearing upstream is an extraction failure rather than a silent wrong pick.
WANTED = [
    (
        "main/physics/collision/Collisions.cpp",
        "Vector3 RoR::primitiveCollision(node_t *node, Ogre::Vector3 velocity, "
        "float mass, Ogre::Vector3 normal, float dt, ground_model_t* gm, float penetration)",
    ),
]

PROLOGUE = """// GENERATED — do not edit. Produced by tools/parity/extract.py from the pinned
// Rigs of Rods submodule. Every function below is upstream's source, unmodified.
//
// Rigs of Rods is GPL-3.0-or-later, as is this project.

#include "rig_types.h"
#include "ApproxMath.h"

#include <algorithm>
#include <cmath>

using namespace Ogre;

namespace RoR {
// Declared so that the extracted definition, which is written as `RoR::primitiveCollision`,
// has something to define.
Vector3 primitiveCollision(node_t *node, Ogre::Vector3 velocity, float mass,
                           Ogre::Vector3 normal, float dt, ground_model_t *gm,
                           float penetration = 0);
} // namespace RoR

"""


def extract(source: Path, signature: str) -> str:
    """The whole definition beginning at `signature`, by brace matching."""
    text = source.read_text(encoding="utf-8", errors="replace")
    # Upstream wraps long signatures; compare with whitespace collapsed so that a reflow does
    # not look like a rename.
    flat = " ".join(signature.split())
    for start in range(len(text)):
        if text[start] != flat[0]:
            continue
        window = " ".join(text[start:start + len(flat) + 200].split())
        if not window.startswith(flat):
            continue
        brace = text.index("{", start)
        depth = 0
        for i in range(brace, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]
        raise SystemExit(f"extract.py: unbalanced braces in {source}")
    raise SystemExit(
        f"extract.py: could not find in {source}:\n    {flat}\n"
        "The pinned upstream has changed shape. Update WANTED rather than editing the output."
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    root = Path(sys.argv[1])
    out = Path(sys.argv[2])
    pieces = [PROLOGUE]
    for relative, signature in WANTED:
        source = root / relative
        if not source.is_file():
            raise SystemExit(f"extract.py: {source} does not exist")
        pieces.append(f"// From {relative}\n{extract(source, signature)}\n")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(pieces), encoding="utf-8")
    print(f"extract.py: wrote {out} from {len(WANTED)} upstream function(s)")


if __name__ == "__main__":
    main()
