// What upstream's `ActorSpawner::ProcessTrigger` reads and calls, with upstream's names: the parsed
// row (`RigDef::Trigger`, its option bits from RigDef_File.h), and the spawner members it uses. The
// one-line setters are upstream's own bodies (ActorSpawner.cpp); `AddBeam` keeps what a trigger's
// beam needs of `GetAndInitFreeBeam` and `AddBeam`.
#pragma once

#include "actor_shocks.h"

#include <memory>
#include <string>

#define BITMASK_IS_1(VAR, FLAGS) (((VAR) & (FLAGS)) == (FLAGS))
using BitMask_t = unsigned int;
using NodeNum_t = int;
static const NodeNum_t NODENUM_INVALID = -1;

namespace fmt {
template <typename... Args> std::string format(const char *, Args &&...) { return std::string(); }
}

namespace RigDef {
struct BeamDefaults {
    float springiness = DEFAULT_SPRING;
    float damping_constant = DEFAULT_DAMP;
    float breaking_threshold = 1000000.0f;
};
struct Trigger {
    static const BitMask_t OPTION_i_INVISIBLE = BITMASK(1);
    static const BitMask_t OPTION_c_COMMAND_STYLE = BITMASK(2);
    static const BitMask_t OPTION_x_START_DISABLED = BITMASK(3);
    static const BitMask_t OPTION_b_KEY_BLOCKER = BITMASK(4);
    static const BitMask_t OPTION_B_TRIGGER_BLOCKER = BITMASK(5);
    static const BitMask_t OPTION_A_INV_TRIGGER_BLOCKER = BITMASK(6);
    static const BitMask_t OPTION_s_CMD_NUM_SWITCH = BITMASK(7);
    static const BitMask_t OPTION_h_UNLOCKS_HOOK_GROUP = BITMASK(8);
    static const BitMask_t OPTION_H_LOCKS_HOOK_GROUP = BITMASK(9);
    static const BitMask_t OPTION_t_CONTINUOUS = BITMASK(10);
    static const BitMask_t OPTION_E_ENGINE_TRIGGER = BITMASK(11);
    int nodes[2] = {0, 0};
    float contraction_trigger_limit = 0.f;
    float expansion_trigger_limit = 0.f;
    BitMask_t options = 0;
    float boundary_timer = 1.f;
    std::shared_ptr<BeamDefaults> beam_defaults;
    int detacher_group = 0;
    int shortbound_trigger_action = 0;
    int longbound_trigger_action = 0;
};
} // namespace RigDef

namespace RoR {
class ActorSpawner {
public:
    struct Message {
        enum Type { TYPE_ERROR, TYPE_WARNING };
    };
    Actor *m_actor = nullptr;
    void ProcessTrigger(RigDef::Trigger &def);
    void AddMessage(int, const std::string &) {}
    NodeNum_t ResolveNodeRef(int ref) { return ref >= 0 && ref < m_actor->ar_num_nodes ? ref : NODENUM_INVALID; }
    beam_t &AddBeam(node_t &node_1, node_t &node_2, std::shared_ptr<RigDef::BeamDefaults> &defaults, int detacher_group) {
        beam_t &beam = m_actor->ar_beams[m_actor->ar_num_beams];
        m_actor->ar_num_beams++;
        beam = beam_t();
        beam.p1 = &node_1;
        beam.p2 = &node_2;
        beam.detacher_group = detacher_group;
        beam.strength = defaults->breaking_threshold;
        beam.minmaxposnegstress = 1.0e30f;
        beam.maxposstress = 1.0e30f;
        beam.maxnegstress = -1.0e30f;
        m_actor->ar_beams_invisible.push_back(false);
        return beam;
    }
    void SetBeamStrength(beam_t &beam, float strength) { beam.strength = strength; }
    void SetBeamSpring(beam_t &beam, float spring) { beam.k = spring; }
    void SetBeamDamping(beam_t &beam, float damping) { beam.d = damping; }
    void CalculateBeamLength(beam_t &beam) {
        float beam_length = (beam.p1->RelPosition - beam.p2->RelPosition).length();
        beam.L = beam_length;
    }
    template <typename... Args> void CreateBeamVisuals(Args &&...) {}
    shock_t &GetFreeShock() {
        shock_t &shock = m_actor->ar_shocks[m_actor->ar_num_shocks];
        m_actor->ar_num_shocks++;
        return shock;
    }
};
} // namespace RoR
