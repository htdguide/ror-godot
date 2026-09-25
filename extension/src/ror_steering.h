#pragma once

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
    int count() const { return static_cast<int>(m_hydros.size()); }

    // Where the driver is asking the wheels to go, -1 to 1.
    void set_command(float command);
    float command() const { return m_command; }
    // Where they have actually got to. Upstream ramps towards the command at a rate that
    // falls with road speed, so a rig cannot be flicked to full lock at 100 km/h, and
    // self-centres towards zero whenever the driver is not asking.
    float state() const { return m_state; }

    void update(float dt, float road_speed, BeamArray &beams);

private:
    struct Hydro {
        int beam = 0;
        float factor = 0.0f;
    };

    std::vector<Hydro> m_hydros;
    float m_command = 0.0f;
    float m_state = 0.0f;
};

} // namespace rorgd
