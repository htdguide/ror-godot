// Runs Rigs of Rods' own contact law, or its shock laws, and prints what they return.
//
// One case per line on stdin, one result per line on stdout, so the comparison can be driven
// from the gate runner without linking anything of ours into anything of upstream's. What is
// executed here is upstream's code, compiled from the pinned submodule.
//
//   in:  vx vy vz fx fy fz mass friction nx ny nz penetration dt
//   out: fx fy fz
//
// A line starting `shock2` or `shock3` runs `Actor::CalcShocks2` / `CalcShocks3` instead:
//
//   in:  shock2 soft_bump L shortbound longbound sbd_spring sbd_damp k d difftoBeamL v rates...
//   out: k d
//
// with the row's rates in its order: shocks2 springin dampin sprogin dprogin springout dampout
// sprogout dprogout; shocks3 springin dampin dslowin splitin dfastin springout dampout dslowout
// splitout dfastout.

#include "rig_types.h"
#include "actor_shocks.h"

#include <sstream>
#include <vector>

#include <cstdio>
#include <iostream>
#include <string>

const Ogre::Vector3 Ogre::Vector3::ZERO = Ogre::Vector3(0.0f, 0.0f, 0.0f);

namespace RoR {
Ogre::Vector3 primitiveCollision(node_t *node, Ogre::Vector3 velocity, float mass,
                                 Ogre::Vector3 normal, float dt, ground_model_t *gm,
                                 float penetration);
}

// One shock case; false if the line is malformed.
static bool run_shock(const std::string &line) {
    std::istringstream in(line);
    std::string kind;
    int soft = 0;
    beam_t beam;
    shock_t shock;
    float k = 0, d = 0, diff = 0, v = 0;
    in >> kind >> soft >> beam.L >> beam.shortbound >> beam.longbound >> shock.sbd_spring >> shock.sbd_damp >> k >>
            d >> diff >> v;
    std::vector<float> r;
    float value = 0;
    while (in >> value) {
        r.push_back(value);
    }
    RoR::Actor actor;
    actor.ar_beams = &beam;
    beam.shock = &shock;
    if (kind == "shock2" && r.size() == 8) {
        shock.flags = soft ? SHOCK_FLAG_SOFTBUMP : SHOCK_FLAG_NORMAL;
        shock.springin = r[0]; shock.dampin = r[1]; shock.sprogin = r[2]; shock.dprogin = r[3];
        shock.springout = r[4]; shock.dampout = r[5]; shock.sprogout = r[6]; shock.dprogout = r[7];
        actor.CalcShocks2(0, diff, k, d, v);
    } else if (kind == "shock3" && r.size() == 10) {
        shock.flags = SHOCK_FLAG_NORMAL;
        shock.springin = r[0]; shock.dampin = r[1]; shock.dslowin = r[2]; shock.splitin = r[3];
        shock.dfastin = r[4]; shock.springout = r[5]; shock.dampout = r[6]; shock.dslowout = r[7];
        shock.splitout = r[8]; shock.dfastout = r[9];
        actor.CalcShocks3(0, diff, k, d, v);
    } else {
        return false;
    }
    std::printf("%.9g %.9g\n", k, d);
    return true;
}

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }
        if (line.rfind("shock", 0) == 0) {
            if (!run_shock(line)) {
                std::fprintf(stderr, "oracle: malformed shock case: %s\n", line.c_str());
                return 2;
            }
            continue;
        }
        float vx, vy, vz, fx, fy, fz, mass, friction, nx, ny, nz, penetration, dt;
        if (std::sscanf(line.c_str(), "%f %f %f %f %f %f %f %f %f %f %f %f %f", &vx, &vy, &vz,
                        &fx, &fy, &fz, &mass, &friction, &nx, &ny, &nz, &penetration,
                        &dt) != 13) {
            std::fprintf(stderr, "oracle: malformed case: %s\n", line.c_str());
            return 2;
        }
        node_t node;
        node.Forces = Ogre::Vector3(fx, fy, fz);
        node.friction_coef = friction;
        ground_model_t ground;
        const Ogre::Vector3 force = RoR::primitiveCollision(
                &node, Ogre::Vector3(vx, vy, vz), mass, Ogre::Vector3(nx, ny, nz), dt, &ground,
                penetration);
        // Enough digits to round-trip a float, so the comparison is against what upstream
        // computed rather than against what printing it lost.
        std::printf("%.9g %.9g %.9g\n", force.x, force.y, force.z);
    }
    return 0;
}
