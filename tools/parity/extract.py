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
    ("main/physics/ActorForcesEuler.cpp", "void Actor::CalcHydros()"),
    ("main/physics/Actor.cpp", "void Actor::CalcAnimators(hydrobeam_t const& hydrobeam, float &cstate, int &div)"),
    ("main/physics/air/Airfoil.cpp", "Airfoil::Airfoil(Ogre::String const& fname)"),
    ("main/physics/air/Airfoil.cpp", "void Airfoil::getparams(float a, float cratio, float cdef, float* ocl, float* ocd, float* ocm)"),
    ("main/physics/flex/FlexAirfoil.cpp", "void FlexAirfoil::setControlDeflection(float val)"),
    ("main/physics/flex/FlexAirfoil.cpp", "void FlexAirfoil::enableInducedDrag(float span, float area, bool l)"),
    ("main/physics/flex/FlexAirfoil.cpp", "void FlexAirfoil::updateForces()"),
    ("main/physics/air/AirBrake.cpp", "void Airbrake::applyForce()"),
    ("main/physics/water/ScrewProp.cpp", "void Screwprop::updateForces(int update)"),
    ("main/physics/water/ScrewProp.cpp", "void Screwprop::setThrottle(float val)"),
    ("main/physics/water/ScrewProp.cpp", "void Screwprop::setRudder(float val)"),
    ("main/physics/water/ScrewProp.cpp", "float Screwprop::getThrottle()"),
    ("main/physics/water/ScrewProp.cpp", "float Screwprop::getRudder()"),
    ("main/physics/water/ScrewProp.cpp", "void Screwprop::reset()"),
    ("main/physics/water/ScrewProp.cpp", "void Screwprop::toggleReverse()"),
    ("main/physics/water/Buoyance.cpp", "BuoyCachedNodeID_t Buoyance::cacheBuoycabNode(node_t* n)"),
    ("main/physics/water/Buoyance.cpp", "inline float Buoyance::computeVolume(Vec3 o, Vec3 a, Vec3 b, Vec3 c)"),
    ("main/physics/water/Buoyance.cpp", "Vec3 Buoyance::computePressureForceSub(Vec3 a, Vec3 b, Vec3 c, Vec3 vel, int type)"),
    ("main/physics/water/Buoyance.cpp", "Vec3 Buoyance::computePressureForce(Vec3 a, Vec3 b, Vec3 c, Vec3 vel, int type)"),
    ("main/physics/ActorForcesEuler.cpp", "void Actor::CalcBuoyance(bool doUpdate)"),
    ("main/physics/water/Buoyance.cpp", "void Buoyance::computeNodeForce(BuoyCachedNode* a, BuoyCachedNode* b, BuoyCachedNode* c, int type, float timeshift)"),
    ("main/gameplay/AutoPilot.cpp", "void Autopilot::setInertialReferences(node_t* refl, node_t* refr, node_t* refb, node_t* refc)"),
    ("main/gameplay/AutoPilot.cpp", "float Autopilot::getAilerons()"),
    ("main/gameplay/AutoPilot.cpp", "float Autopilot::getElevator()"),
    ("main/gameplay/AutoPilot.cpp", "float Autopilot::getThrottle(float thrtl, float dt)"),
    ("main/gameplay/AutoPilot.cpp", "int Autopilot::toggleHeading(int mode)"),
    ("main/gameplay/AutoPilot.cpp", "int Autopilot::toggleAlt(int mode)"),
    ("main/gameplay/AutoPilot.cpp", "bool Autopilot::toggleIAS()"),
    ("main/gameplay/AutoPilot.cpp", "int Autopilot::adjHDG(int d)"),
    ("main/gameplay/AutoPilot.cpp", "int Autopilot::adjALT(int d)"),
    ("main/gameplay/AutoPilot.cpp", "int Autopilot::adjVS(int d)"),
    ("main/gameplay/AutoPilot.cpp", "int Autopilot::adjIAS(int d)"),
    ("main/physics/air/TurboProp.cpp", "void Turboprop::updateForces(float dt, int doUpdate)"),
    ("main/physics/air/TurboProp.cpp", "void Turboprop::setThrottle(float val)"),
    ("main/physics/air/TurboProp.cpp", "void Turboprop::reset()"),
    ("main/physics/air/TurboProp.cpp", "void Turboprop::toggleReverse()"),
    ("main/physics/air/TurboProp.cpp", "void Turboprop::flipStart()"),
    ("main/physics/air/TurboJet.cpp", "Turbojet::Turbojet(ActorPtr actor, NodeNum_t tnodefront, NodeNum_t tnodeback, NodeNum_t tnoderef, RigDef::Turbojet & def)"),
    ("main/physics/air/TurboJet.cpp", "void Turbojet::updateForces(float dt, int doUpdate)"),
    ("main/physics/air/TurboJet.cpp", "void Turbojet::setThrottle(float val)"),
    ("main/physics/air/TurboJet.cpp", "void Turbojet::reset()"),
    ("main/physics/air/TurboJet.cpp", "void Turbojet::toggleReverse()"),
    ("main/physics/air/TurboJet.cpp", "void Turbojet::flipStart()"),
    ("main/physics/air/TurboJet.cpp", "void Turbojet::setRPM(float _rpm)"),
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
    # `updateVerticesPhysics`' break test: its three vectors (upstream's lines above it) and its
    # two lines, the `else` lifted by the next block.
    (
        "main/physics/flex/FlexAirfoil.cpp",
        "if (breakable) {broken=",
        "void FlexAirfoil::updateBroken()\n{\n"
        "    Vector3 vx=nodes[nfrd].AbsPosition-nodes[nfld].AbsPosition;\n"
        "    Vector3 vzl=nodes[nbld].AbsPosition-nodes[nfld].AbsPosition;\n"
        "    Vector3 vzr=nodes[nbrd].AbsPosition-nodes[nfrd].AbsPosition;\n    ",
        "\n",
    ),
    (
        "main/physics/flex/FlexAirfoil.cpp",
        "else {broken=(vx.crossProduct(vzl)",
        "    ",
        "\n}\n",
    ),
]

# Single lines lifted whole, a file-scope constant a lifted function reads: (file, the line's start).
# The start must name exactly one line.
LINES = [
    ("main/physics/ActorForcesEuler.cpp", "const int BUOYANCY_SAMPLING_INTERVAL"),
    ("main/physics/ActorForcesEuler.cpp", "const int BUOYANCY_VISUAL_UPDATE_INTERVAL"),
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
#include "flex_airfoil.h"
#include "aero_engines.h"
#include "autopilot.h"

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
    for relative, start in LINES:
        found = [l for l in (root / relative).read_text(encoding="utf-8", errors="replace").splitlines() if l.startswith(start)]
        if len(found) != 1:
            raise SystemExit(f"extract.py: {len(found)} lines in {relative} start with {start!r}, not one")
        pieces.append(f"// From {relative}, one line\n{found[0]}\n")
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
