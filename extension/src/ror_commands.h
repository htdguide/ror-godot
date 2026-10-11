#pragma once

#include "ror_inertia.h"
#include "ror_node.h"

#include <array>
#include <cstdint>
#include <vector>

namespace rorgd {

// Upstream's `MAX_COMMANDS`: command keys are numbered 1 to this.
constexpr int MAX_COMMAND_KEYS = 84;

// One ram's state, shared by its contraction and its extension: upstream's `commandbeam_state_t`.
struct RorCommandState {
    int auto_moving_mode = 0;
    bool pressed_center_mode = false;
    bool auto_move_lock = false;
};

// One direction of one ram on one key: upstream's `commandbeam_t`.
struct RorCommandBeam {
    int beam = -1;
    bool contraction = false;
    float speed = 0.0f;
    // The length the ram stops at, as a fraction of the beam's reference length.
    float boundary = 1.0f;
    float center = 1.0f;
    bool force_restricted = false;
    bool auto_center = false;
    bool needs_engine = true;
    bool one_press = false;
    bool one_press_center = false;
    float engine_coupling = 1.0f;
    int state = 0;
};

struct RorCommandKey {
    std::vector<RorCommandBeam> beams;
    float player_input = 0.0f;
    float value = 0.0f;
    RorKeyInertia inertia;
};

// The key-driven rams of one actor: upstream's `Actor::CalcCommands`, beams only (rotators are not
// built here). Each substep a held key moves its rams' rest lengths at their rate, scaled by the
// engine's crank factor when they draw on it, until they reach their boundary; a one-press ram
// keeps going on its own once tapped, and an auto-centering one returns to its middle when let go.
class RorCommands {
public:
    void add(int beam, int contract_key, int extend_key, float shorten_rate, float lengthen_rate,
             float max_contraction, float max_extension, bool force_restricted, bool auto_center,
             bool one_press, bool one_press_center, float engine_coupling, bool needs_engine);
    void set_key(int key, float value);
    // Upstream's inertia models, by name, and a key's inertia from them: `ActorSpawner::
    // _ProcessKeyInertia` decides which delays and names a key gets, and a name not among the
    // models leaves that curve as it was.
    void add_inertia_model(const std::string &name, const std::vector<float> &x, const std::vector<float> &y);
    void set_key_inertia(int key, float start_delay, float stop_delay, const std::string &start,
                         const std::string &stop);
    bool key_has_inertia(int key) const;
    bool empty() const { return m_count == 0; }
    int count() const { return m_count; }

    struct Power {
        bool requested = false;
        float work = 0.0f;
    };
    // One substep. `hydraulics_ready` is upstream's engine-running-above-95%-of-idle test; with
    // no engine pass true and a crank factor of 1.
    Power update(BeamArray &beams, float dt, bool engine_running, bool hydraulics_ready,
                 float crank_factor);

private:
    std::array<RorCommandKey, MAX_COMMAND_KEYS + 1> m_keys{};
    std::vector<RorCommandState> m_states;
    RorInertiaModels m_models;
    int m_count = 0;
};

} // namespace rorgd
