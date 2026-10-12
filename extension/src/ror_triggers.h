#pragma once

namespace rorgd {

// Upstream's trigger flags (`SHOCK_FLAG_*` of SimData.h), by their own bits.
enum RorTriggerFlag : int {
    TRIGGER_FLAG_NORMAL = 1 << 1,
    TRIGGER_FLAG_IS_TRIGGER = 1 << 8,
    TRIGGER_FLAG_BLOCKER = 1 << 9,
    TRIGGER_FLAG_CMD_SWITCH = 1 << 10,
    TRIGGER_FLAG_CMD_BLOCKER = 1 << 11,
    TRIGGER_FLAG_BLOCKER_A = 1 << 12,
    TRIGGER_FLAG_HOOK_UNLOCK = 1 << 13,
    TRIGGER_FLAG_HOOK_LOCK = 1 << 14,
    TRIGGER_FLAG_CONTINUOUS = 1 << 15,
    TRIGGER_FLAG_ENGINE = 1 << 16,
};

// Upstream's `EngineTriggerType`.
enum RorEngineTrigger : int {
    ENGINE_TRIGGER_CLUTCH = 0,
    ENGINE_TRIGGER_BRAKE = 1,
    ENGINE_TRIGGER_ACC = 2,
    ENGINE_TRIGGER_RPM = 3,
    ENGINE_TRIGGER_SHIFTUP = 4,
    ENGINE_TRIGGER_SHIFTDOWN = 5,
};

// The trigger half of upstream's `shock_t`: what a `triggers` row's beam does when it is squeezed
// or stretched past its bounds (`Actor::CalcTriggers`).
struct RorTrigger {
    int beam = -1;
    int flags = 0;
    bool enabled = true;
    // Upstream's `trigger_switch_state`, a flag and a countdown in one.
    float switch_state = 0.0f;
    float boundary_t = 1.0f;
    int cmd_short = 0;
    int cmd_long = 0;
};

} // namespace rorgd
