#pragma once

namespace rorgd {

class RorSolver;

// Upstream's `hook_t`: a node with option `h` and the rope beam it locks with. Its beam lives in
// its own solver's beams; locked to another vehicle, the beam's far end is `lock_node` of `target`
// and the world works its force out (`RorWorld`), as upstream's `CalcBeamsInterActor` does.
struct RorHook {
    enum class State { UNLOCKED, PRELOCK, LOCKED };
    // Upstream's `ActorLinkingRequestType` for hooks.
    enum Mode { LOCK = 0, UNLOCK = 1, TOGGLE = 2, RESET = 3 };

    int node = -1;
    int beam = -1;
    // Upstream's defaults (`SimConstants.h`, `ProcessNode`).
    int group = -1;
    int lockgroup = -1;
    bool selflock = false;
    bool autolock = false;
    bool nodisable = false;
    float maxforce = 10000000.0f;
    float lockrange = 0.4f;
    float lockspeed = 0.00025f;
    float timer = 0.0f;
    float timer_preset = 5.0f;
    float min_length = 0.0f;
    State state = State::UNLOCKED;
    // What it is locked to: another solver (null for its own), and that solver's node.
    RorSolver *target = nullptr;
    int lock_node = -1;
    // Where its beam's far end is: set when the beam is enabled and not after, as upstream's.
    RorSolver *beam_target = nullptr;
    int beam_node = -1;
};

// Upstream's `HOOK_RANGE_DEFAULT` and `HOOK_SPEED_DEFAULT`.
constexpr float HOOK_RANGE = 0.4f;
constexpr float HOOK_SPEED = 0.00025f;

// Upstream's `ropable_t`: a node ties and ropes may take, by group, one at a time unless it is
// `multilock`.
struct RorRopable {
    int node = -1;
    int group = -1;
    bool multilock = false;
    int attached_ties = 0;
    int attached_ropes = 0;
};

// Upstream's `rope_t`: a `ropes` beam whose end node, locked, rides on the nearest free ropable
// within the beam's length. Its group is upstream's hard-coded 0.
struct RorRope {
    int beam = -1;
    int group = 0;
    bool locked = false;
    // The ropable it is locked to: on another solver (null for its own), by index there.
    RorSolver *target = nullptr;
    int ropable = -1;
};

// Upstream's `tie_t`: a rope from `root` that reaches up to its beam's reference length for the
// nearest free ropable, then shortens at `contract_speed` until it is `min_length` of that length
// or pulls harder than `max_stress`.
struct RorTie {
    int beam = -1;
    int group = -1;
    float contract_speed = 0.0f;
    float max_stress = 100000.0f;
    float min_length = 0.0f;
    bool no_self_lock = false;
    bool tied = false;
    bool tying = false;
    // The ropable it is tied to: on another solver (null for its own), by index there.
    RorSolver *target = nullptr;
    int ropable = -1;
};

// Upstream's lock group that no hook may take (`LOCKGROUP_NOLOCK`).
constexpr int LOCKGROUP_NOLOCK = 9999;

} // namespace rorgd
