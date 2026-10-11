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
//
// A line starting `beams` runs `Actor::CalcBeams` on the rig that follows, `passes` times with
// the forces cleared before each and the nodes left where they are:
//
//   in:  beams passes node_count beam_count
//        node x y z vx vy vz cab                                  (node_count lines)
//        beam p1 p2 L k d bounded bm_type shortbound longbound sbd_spring sbd_damp deform
//             strength plastic_coef                               (beam_count lines)
//   out: one line per node: fx fy fz; then one per beam: L stress strength broken
//
// A line starting `diff` runs one of `Differential`'s four laws:
//
//   in:  diff <s|o|v|l> speed0 speed1 in_torque dt delta_rotation
//   out: out_torque0 out_torque1 delta_rotation

#include "rig_types.h"
#include "actor_shocks.h"
#include "differentials.h"

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

// One differential case; false if the line is malformed.
static bool run_diff(const std::string &line) {
    char type = 0;
    RoR::DifferentialData data{};
    if (std::sscanf(line.c_str(), "diff %c %f %f %f %f %f", &type, &data.speed[0], &data.speed[1], &data.in_torque,
                    &data.dt, &data.delta_rotation) != 6) {
        return false;
    }
    switch (type) {
    case 's': RoR::Differential::CalcSeparateDiff(data); break;
    case 'o': RoR::Differential::CalcOpenDiff(data); break;
    case 'v': RoR::Differential::CalcViscousDiff(data); break;
    case 'l': RoR::Differential::CalcLockedDiff(data); break;
    default: return false;
    }
    std::printf("%.9g %.9g %.9g\n", data.out_torque[0], data.out_torque[1], data.delta_rotation);
    return true;
}

// One rig of beams; false if the block is malformed.
static bool run_beams(const std::string &header) {
    int passes = 0, node_count = 0, beam_count = 0;
    if (std::sscanf(header.c_str(), "beams %d %d %d", &passes, &node_count, &beam_count) != 3) {
        return false;
    }
    std::vector<node_t> nodes(static_cast<size_t>(node_count));
    std::vector<shock_t> shocks(static_cast<size_t>(beam_count));
    RoR::Actor actor;
    actor.beams.resize(static_cast<size_t>(beam_count));
    actor.ar_node_to_beam_connections.resize(static_cast<size_t>(node_count));
    std::string line;
    for (int i = 0; i < node_count; ++i) {
        int cab = 0;
        node_t &n = nodes[static_cast<size_t>(i)];
        if (!std::getline(std::cin, line) ||
            std::sscanf(line.c_str(), "node %f %f %f %f %f %f %d", &n.RelPosition.x, &n.RelPosition.y,
                        &n.RelPosition.z, &n.Velocity.x, &n.Velocity.y, &n.Velocity.z, &cab) != 7) {
            return false;
        }
        n.nd_cab_node = cab != 0;
        n.pos = i;
    }
    for (int i = 0; i < beam_count; ++i) {
        int p1 = 0, p2 = 0, bounded = 0, type = 0;
        float deform = 0;
        beam_t &b = actor.beams[static_cast<size_t>(i)];
        shock_t &shock = shocks[static_cast<size_t>(i)];
        if (!std::getline(std::cin, line) ||
            std::sscanf(line.c_str(), "beam %d %d %f %f %f %d %d %f %f %f %f %f %f %f", &p1, &p2, &b.L, &b.k, &b.d,
                        &bounded, &type, &b.shortbound, &b.longbound, &shock.sbd_spring, &shock.sbd_damp, &deform,
                        &b.strength, &b.plastic_coef) != 14) {
            return false;
        }
        b.p1 = &nodes[static_cast<size_t>(p1)];
        b.p2 = &nodes[static_cast<size_t>(p2)];
        b.bounded = static_cast<SpecialBeam>(bounded);
        b.bm_type = static_cast<BeamType>(type);
        // As upstream's spawner sets them (`SetBeamDeformationThreshold`).
        b.maxposstress = deform;
        b.maxnegstress = -deform;
        b.minmaxposnegstress = deform;
        b.shock = &shock;
        actor.ar_node_to_beam_connections[static_cast<size_t>(p1)].push_back(i);
        actor.ar_node_to_beam_connections[static_cast<size_t>(p2)].push_back(i);
    }
    actor.ar_beams = actor.beams.data();
    actor.ar_num_beams = beam_count;
    actor.ar_nodes = nodes.data();
    for (int pass = 0; pass < passes; ++pass) {
        for (node_t &n : nodes) {
            n.Forces = Ogre::Vector3(0.0f, 0.0f, 0.0f);
        }
        actor.CalcBeams(false);
    }
    for (const node_t &n : nodes) {
        std::printf("%.9g %.9g %.9g\n", n.Forces.x, n.Forces.y, n.Forces.z);
    }
    for (const beam_t &b : actor.beams) {
        std::printf("%.9g %.9g %.9g %d\n", b.L, b.stress, b.strength, b.bm_broken ? 1 : 0);
    }
    return true;
}

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }
        if (line.rfind("beams", 0) == 0) {
            if (!run_beams(line)) {
                std::fprintf(stderr, "oracle: malformed beams block: %s\n", line.c_str());
                return 2;
            }
            continue;
        }
        if (line.rfind("diff", 0) == 0) {
            if (!run_diff(line)) {
                std::fprintf(stderr, "oracle: malformed diff case: %s\n", line.c_str());
                return 2;
            }
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
