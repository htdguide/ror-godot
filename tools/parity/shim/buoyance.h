// What upstream's `Buoyance` (physics/water/Buoyance.h) holds, with its names and types, without
// its particles and debug view. Its methods are upstream's, lifted by extract.py. The sea it asks
// is flat: `Wavefield::CalcWavesHeight` with waves off, upstream's default, is the static height.
#pragma once

#include "../utils/Vec3.h"
#include "rig_types.h"

#include <cstdint>
#include <vector>

namespace RoR {
using NodeNum_t = int; // As spawner_trigger.h has it; upstream's is uint16_t, which every node index here fits.
typedef int BuoyCachedNodeID_t;
struct DustPool {
    void malloc(Vec3, Vec3) {}
    void allocSplash(Ogre::Vector3, Ogre::Vector3) {}
    void allocRipple(Ogre::Vector3, Ogre::Vector3) {}
};
struct BuoyCachedNode {
    BuoyCachedNode(NodeNum_t _nodenum) : nodenum(_nodenum) {}
    Vec3 AbsPosition;
    Vec3 Velocity;
    Vec3 Forces;
    NodeNum_t nodenum = 0;
};
struct BuoyDebugSubCab {
    BuoyDebugSubCab(Vec3 _a, Vec3 _b, Vec3 _c, Vec3 _norm, Vec3 _drag, float _volume)
        : a(_a), b(_b), c(_c), normal(_norm), drag(_drag), volume(_volume) {}
    Vec3 a, b, c, normal, drag;
    float volume;
};
class Buoyance {
public:
    void computeNodeForce(BuoyCachedNode *a, BuoyCachedNode *b, BuoyCachedNode *c, int type, float timeshift);
    enum { BUOY_NORMAL, BUOY_DRAGONLY, BUOY_DRAGLESS };
    bool sink = false;
    bool update = false;
    BuoyCachedNodeID_t cacheBuoycabNode(node_t *n);
    std::vector<BuoyCachedNode> buoy_cached_nodes;
    std::vector<BuoyCachedNode> buoy_projected_nodes;
    bool buoy_debug_view = false;
    std::vector<BuoyDebugSubCab> buoy_debug_subcabs;
    long long buoy_total_steps = 0;
    long long buoy_last_sample_steps = 0;
    inline float computeVolume(Vec3 o, Vec3 a, Vec3 b, Vec3 c);
    Vec3 computePressureForceSub(Vec3 a, Vec3 b, Vec3 c, Vec3 vel, int type);
    Vec3 computePressureForce(Vec3 a, Vec3 b, Vec3 c, Vec3 vel, int type);
    DustPool *splashp = nullptr, *ripplep = nullptr;
};
// The sea, flat at a case's height.
struct Wavefield {
    float height = 0;
    float CalcWavesHeight(Vec3, float = 0.f) { return height; }
    Vec3 CalcWavesVelocity(Vec3, float = 0.f) { return Vec3(); }
};
struct Terrain {
    Wavefield *water = nullptr;
    Wavefield *getWater() { return water; }
};
} // namespace RoR
