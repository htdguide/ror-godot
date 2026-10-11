// The part of Rigs of Rods' Actor that its beam laws read: `CalcBeams`, `CalcShocks2`,
// `CalcShocks3` and `GetNumActiveConnectedBeams`.
//
// All are member functions reading `ar_beams[i]` and what it points at. Declaring an Actor with
// only those members lets them be compiled from upstream's source unmodified. Names, types, enum
// values and constants are upstream's (SimData.h, SimConstants.h, BitFlags.h); a rename there
// breaks this build, which is the point. The debug, sound and console paths are compiled but
// stubbed: the oracle runs with every debug flag off and nothing to play.
#pragma once

#include "OgreVector3.h"
#include "rig_types.h"

#include <algorithm>
#include <cmath>
#include <sstream>
#include <string>
#include <vector>

using Ogre::Real;

namespace Ogre {
struct Math {
    // OgreMath.h: `std::max(std::min(val, maxval), minval)`.
    template <typename T> static T Clamp(T val, T minval, T maxval) {
        return std::max(std::min(val, maxval), minval);
    }
};
} // namespace Ogre

#define BITMASK( OFFSET ) ( 1 << ((OFFSET) - 1) )

// SimConstants.h
static const float DEFAULT_SPRING = 9000000.0f;
static const float DEFAULT_DAMP = 12000.0f;
static const float MIN_BEAM_LENGTH = 0.1f;
static const float SUPPORT_BEAM_LIMIT_DEFAULT = 4.0f;

// SimData.h
enum BeamType : short { BEAM_NORMAL, BEAM_HYDRO, BEAM_VIRTUAL };
enum SpecialBeam : short { NOSHOCK, SHOCK1, SHOCK2, SHOCK3, TRIGGER, SUPPORTBEAM, ROPE };
enum ShockFlags {
    SHOCK_FLAG_NORMAL = BITMASK(1),
    SHOCK_FLAG_ISSHOCK2 = BITMASK(5),
    SHOCK_FLAG_ISSHOCK3 = BITMASK(6),
    SHOCK_FLAG_SOFTBUMP = BITMASK(7),
};

struct shock_t {
    int flags = 0;
    float springin = 0, dampin = 0, springout = 0, dampout = 0;
    float sprogin = 0, dprogin = 0, sprogout = 0, dprogout = 0;
    float splitin = 0, dslowin = 0, dfastin = 0, splitout = 0, dslowout = 0, dfastout = 0;
    float sbd_spring = 0, sbd_damp = 0;
};

struct beam_t {
    node_t *p1 = nullptr;
    node_t *p2 = nullptr;
    float k = 0, d = 0, L = 0;
    float minmaxposnegstress = 0, maxposstress = 0, maxnegstress = 0;
    float strength = 0, stress = 0, plastic_coef = 0;
    float shortbound = 0, longbound = 0;
    int detacher_group = 0;
    SpecialBeam bounded = NOSHOCK;
    BeamType bm_type = BEAM_NORMAL;
    bool bm_inter_actor = false, bm_disabled = false, bm_broken = false;
    float debug_k = 0, debug_d = 0, debug_v = 0;
    shock_t *shock = nullptr;
};

struct wheel_t {
    bool wh_is_detached = false;
};
struct wheeldetacher_t {
    int wd_wheel_id = 0;
    int wd_detacher_group = 0;
};

// The diagnostics CalcBeams writes when its debug flags are on. They are off in the oracle; these
// exist so the code that would write them compiles.
#define SOUND_MODULATE(...) ((void)0)
#define SOUND_PLAY_ONCE(...) ((void)0)
#define TOSTRING(x) std::to_string(x)

namespace RoR {
template <size_t N> struct Str {
    std::ostringstream out;
    template <typename T> Str &operator<<(const T &value) { out << value; return *this; }
    std::string text;
    const char *ToCStr() { text = out.str(); return text.c_str(); }
};
inline void Log(const char *) {}
struct Console {
    enum MessageType { CONSOLE_MSGTYPE_ACTOR };
    enum MessageArea { CONSOLE_SYSTEM_NOTICE };
    void putMessage(int, int, const std::string &) {}
};
namespace App {
inline Console *GetConsole() { static Console console; return &console; }
}
struct Buoyance {
    enum { BUOY_NORMAL, BUOY_DRAGONLY, BUOY_DRAGLESS };
    bool sink = false;
};

class Actor {
public:
    std::vector<beam_t> beams;
    beam_t *ar_beams = nullptr;
    int ar_num_beams = 0;
    node_t *ar_nodes = nullptr;
    std::vector<std::vector<int>> ar_node_to_beam_connections;
    wheel_t *ar_wheels = nullptr;
    std::vector<wheeldetacher_t> ar_wheeldetachers;
    int ar_num_buoycabs = 0;
    int *ar_buoycabs = nullptr;
    int *ar_buoycab_types = nullptr;
    int *ar_cabs = nullptr;
    Buoyance *m_buoyance = nullptr;
    int ar_instance_id = 0;
    bool m_beam_break_debug_enabled = false;
    bool m_beam_deform_debug_enabled = false;

    template <size_t N> void LogBeamNodes(Str<N> &, beam_t &) {}
    void CalcTriggers(int, Real, bool) {}
    void CalcBeams(bool trigger_hooks);
    int GetNumActiveConnectedBeams(int nodeid);
    void CalcShocks2(int i, Real difftoBeamL, Real &k, Real &d, Real v);
    void CalcShocks3(int i, Real difftoBeamL, Real &k, Real &d, Real v);
};
} // namespace RoR
