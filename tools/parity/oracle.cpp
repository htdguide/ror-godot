// Runs Rigs of Rods' own contact law and prints what it returns.
//
// One case per line on stdin, one result per line on stdout, so the comparison can be driven
// from the gate runner without linking anything of ours into anything of upstream's. What is
// executed here is upstream's code, compiled from the pinned submodule.
//
//   in:  vx vy vz fx fy fz mass friction nx ny nz penetration dt
//   out: fx fy fz

#include "rig_types.h"

#include <cstdio>
#include <iostream>
#include <string>

const Ogre::Vector3 Ogre::Vector3::ZERO = Ogre::Vector3(0.0f, 0.0f, 0.0f);

namespace RoR {
Ogre::Vector3 primitiveCollision(node_t *node, Ogre::Vector3 velocity, float mass,
                                 Ogre::Vector3 normal, float dt, ground_model_t *gm,
                                 float penetration);
}

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty() || line[0] == '#') {
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
