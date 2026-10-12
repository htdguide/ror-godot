#pragma once

#include "ror_inertia.h"
#include "ror_node.h"

#include <array>
#include <cstdint>
#include <unordered_map>
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
    // What a trigger beam asked of the key since the last command pass (upstream's
    // `triggerInputValue`), and whether triggers are kept off it (`trigger_cmdkeyblock_state`).
    float trigger_input = 0.0f;
    bool trigger_blocked = false;
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
    // A key's inertia: `ActorSpawner::_ProcessKeyInertia` decides which delays and curves a key
    // gets, and a null curve leaves that one as it was.
    void set_key_inertia(int key, float start_delay, float stop_delay, const RorSpline *start,
                         const RorSpline *stop);
    bool key_has_inertia(int key) const;
    // Upstream's `CmdKeyArray`: keys 0 to 84 are real, a negative one is a 'virtual' key made on
    // first use, and anything above is a dummy.
    RorCommandKey &key(int index);
    // `CalcCommands`' first line for every key: its value is the larger of the player's and the
    // triggers' input, and the triggers' is used up.
    void read_keys();
    // Upstream's `SyncReset`: every key let go and every ram's one-press state cleared. Key
    // inertia is not reset there, so it is not here.
    void reset();
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
    std::unordered_map<int, RorCommandKey> m_virtual_keys;
    RorCommandKey m_dummy_key;
    std::vector<RorCommandState> m_states;
    int m_count = 0;
};

} // namespace rorgd
