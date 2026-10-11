#pragma once

#include <map>
#include <string>
#include <vector>

namespace rorgd {

// Ogre's `SimpleSpline`, for its y only: a Hermite curve through the points with Catmull-Rom
// tangents, and `interpolate(t)` spreading t evenly over the segments, whatever their x. Upstream's
// inertia models are read into these.
class RorSpline {
public:
    void add_point(float x, float y);
    float interpolate_y(float t) const;
    bool empty() const { return m_x.empty(); }

private:
    void recalc_tangents();
    std::vector<float> m_x;
    std::vector<float> m_y;
    std::vector<float> m_tangent_y;
};

// One command key's inertia: upstream's `CmdKeyInertia`. The key's output follows its input not at
// once but by a start curve when it is rising in magnitude and a stop curve when falling, each
// climbing by the curve's value times 0.001 a call, read at (delay factor x time since the output
// last met the input). With either curve missing the input passes straight through.
class RorKeyInertia {
public:
    void configure(float start_delay, float stop_delay, const RorSpline *start, const RorSpline *stop);
    float calc(float input, float dt);
    void reset() {
        m_last_output = 0.0f;
        m_time = 0.0f;
    }
    bool active() const { return m_start != nullptr && m_stop != nullptr; }

private:
    float m_start_delay = 0.0f;
    float m_stop_delay = 0.0f;
    float m_last_output = 0.0f;
    float m_time = 0.0f;
    const RorSpline *m_start = nullptr;
    const RorSpline *m_stop = nullptr;
};

// Upstream's `CmdKeyInertiaConfig`: the named curves. A map, so a key's pointer into it stays put.
using RorInertiaModels = std::map<std::string, RorSpline>;

} // namespace rorgd
