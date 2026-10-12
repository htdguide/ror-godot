#pragma once

#include "ror_animators.h"
#include "ror_inertia.h"
#include "ror_node.h"

namespace rorgd {

// The steering rams, and the rest of the rig's hydraulically actuated beams.
//
// A `hydros` row is a beam with a factor, and steering happens by changing that beam's
// rest length: `L = reference_length * (1 - state * factor)`. Nothing pushes the wheels
// directly. The rams shorten and lengthen, the steering arms they are attached to move,
// and the rig's own structure turns the hubs — which is why a bent steering arm steers
// badly and why a broken ram stops steering at all.
//
// Read as a plain beam a hydro is structurally right and functionally inert: it holds the
// rack but never moves it.
class RorSteering {
public:
    // `factor` is the row's stated fraction of rest length, signed: the rams on opposite
    // sides of a rack carry opposite signs so one pushes while the other pulls.
    void add_hydro(int beam_index, float factor);
    // An `animators` row: a hydro moved by what `flags` (upstream's `hb_anim_flags`) read rather
    // than by the steering, its factor clamped by its beam's own bounds. Returns its hydro index.
    int add_animator(int beam_index, float factor, uint32_t flags, float param);
    int count() const { return static_cast<int>(m_hydros.size()); }

    // Where the driver is asking the wheels to go, -1 to 1.
    void set_command(float command);
    float command() const { return m_command; }
    // Where they have actually got to. Upstream ramps towards the command at a rate that
    // falls with road speed, so a rig cannot be flicked to full lock at 100 km/h, and
    // self-centres towards zero whenever the driver is not asking.
    float state() const { return m_state; }

    // `inputs` is what the animators read this substep; null when the vehicle has none.
    void update(float dt, float road_speed, BeamArray &beams, const RorAnimatorInputs *inputs = nullptr);
    bool has_animators() const { return m_animators > 0; }
    const RorAnimatorMemory &animator_memory() const { return m_memory; }
    // Upstream's `hb_inertia`: a hydro's state follows the steering through its own inertia.
    void set_hydro_inertia(int hydro, float start_delay, float stop_delay, const RorSpline *start,
                           const RorSpline *stop);
    bool hydro_has_inertia(int hydro) const;
    // Upstream's `SyncReset`: the steering straight and each hydro's inertia at rest.
    void reset();

private:
    struct Hydro {
        int beam = 0;
        float factor = 0.0f;
        uint32_t anim_flags = 0;
        float anim_param = 0.0f;
        RorKeyInertia inertia;
    };
    int m_animators = 0;
    RorAnimatorMemory m_memory;

    std::vector<Hydro> m_hydros;
    float m_command = 0.0f;
    float m_state = 0.0f;
};

} // namespace rorgd
