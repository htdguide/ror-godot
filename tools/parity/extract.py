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
    (
        "main/physics/Actor.cpp",
        "void Actor::CalcShocks2(int i, Real difftoBeamL, Real& k, Real& d, Real v)",
    ),
    (
        "main/physics/Actor.cpp",
        "void Actor::CalcShocks3(int i, Real difftoBeamL, Real &k, Real& d, Real v)",
    ),
    ("main/physics/ActorForcesEuler.cpp", "void Actor::CalcBeams(bool trigger_hooks)"),
    ("main/physics/ActorForcesEuler.cpp", "void Actor::CalcWheels(bool doUpdate, int num_steps)"),
    ("main/physics/ActorForcesEuler.cpp", "void Actor::CalcFuseDrag()"),
    ("main/physics/Actor.cpp", "int Actor::GetNumActiveConnectedBeams(int nodeid)"),
    ("main/physics/Differentials.cpp", "void Differential::CalcSeparateDiff(DifferentialData& diff_data)"),
    ("main/physics/Differentials.cpp", "void Differential::CalcOpenDiff(DifferentialData& diff_data)"),
    ("main/physics/Differentials.cpp", "void Differential::CalcViscousDiff(DifferentialData& diff_data)"),
    ("main/physics/Differentials.cpp", "void Differential::CalcLockedDiff(DifferentialData& diff_data)"),
    (
        "main/physics/SlideNode.cpp",
        "Ogre::Vector3 NearestPointOnLine(const Ogre::Vector3& pt1, const Ogre::Vector3& pt2, const Ogre::Vector3& tp)",
    ),
    ("main/physics/SlideNode.cpp", "SlideNode::SlideNode(node_t* slidingNode, RailGroup* slidingRail):"),
    ("main/physics/SlideNode.cpp", "void SlideNode::UpdateForces(float dt)"),
    ("main/physics/SlideNode.cpp", "RailSegment* RailGroup::FindClosestSegment(const Ogre::Vector3& point)"),
    ("main/physics/SlideNode.cpp", "RailSegment* RailSegment::CheckCurSlideSegment(const Ogre::Vector3& point)"),
    ("main/physics/SlideNode.cpp", "void SlideNode::UpdatePosition()"),
    ("main/physics/SlideNode.cpp", "void SlideNode::ResetPositions()"),
    ("main/physics/SlideNode.cpp", "Ogre::Real SlideNode::getLenTo(const RailSegment* rail, const Ogre::Vector3& point)"),
    ("main/physics/SlideNode.cpp", "Ogre::Real SlideNode::getLenTo(const beam_t* beam, const Ogre::Vector3& point)"),
    ("main/physics/SlideNode.cpp", "Ogre::Vector3 SlideNode::CalcCorrectiveForces()"),
    (
        "main/gameplay/Engine.cpp",
        "void Engine::SetTurboOptions(int type, float tinertiaFactor, int nturbos, float param1, float param2, "
        "float param3, float param4, float param5, float param6, float param7, float param8, float param9, "
        "float param10, float param11)",
    ),
    ("main/gameplay/Engine.cpp", "float Engine::getTurboPSI()"),
    ("main/gameplay/Engine.cpp", "float Engine::getTurboPower()"),
    ("main/physics/Actor.cpp", "void Actor::CalcTriggers(int i, Real difftoBeamL, bool trigger_hooks)"),
    ("main/physics/Actor.cpp", "void Actor::engineTriggerHelper(int engineNumber, EngineTriggerType type, float triggerValue)"),
    ("main/physics/ActorSpawner.cpp", "void ActorSpawner::ProcessTrigger(RigDef::Trigger & def)"),
]

# Blocks lifted out of a longer function, each given a function of its own: (source, the block's
# first line, what goes before it, what goes after it).
BLOCKS = [
    (
        "main/gameplay/Engine.cpp",
        "if (m_engine_has_turbo)",
        "void Engine::UpdateTurbo(float dt, float acc)\n{\n",
        "\n}\n\nvoid reset_frand() { mirand = 1; }\n",
    ),
]

PROLOGUE = """// GENERATED — do not edit. Produced by tools/parity/extract.py from the pinned
// Rigs of Rods submodule. Every function below is upstream's source, unmodified.
//
// Rigs of Rods is GPL-3.0-or-later, as is this project.

#include "rig_types.h"
#include "actor_shocks.h"
#include "differentials.h"
#include "ApproxMath.h"
#include "SlideNode.h"
#include "engine_turbo.h"
#include "spawner_trigger.h"

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

// The shock laws are written as `Actor::...`, members of RoR's Actor.
using namespace RoR;

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
    for relative, first_line, before, after in BLOCKS:
        source = root / relative
        pieces.append(f"// From {relative}, a block of a longer function\n{before}{extract(source, first_line)}{after}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(pieces), encoding="utf-8")
    print(f"extract.py: wrote {out} from {len(WANTED)} upstream function(s)")


if __name__ == "__main__":
    main()
