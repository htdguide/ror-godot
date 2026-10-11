#include "ror_inertia.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

void RorSpline::add_point(float x, float y) {
    m_x.push_back(x);
    m_y.push_back(y);
    recalc_tangents();
}

void RorSpline::recalc_tangents() {
    const size_t count = m_x.size();
    m_tangent_y.assign(count, 0.0f);
    if (count < 2) {
        return;
    }
    // Ogre calls the curve closed when its first and last points coincide.
    const bool closed = m_x[0] == m_x[count - 1] && m_y[0] == m_y[count - 1];
    for (size_t i = 0; i < count; ++i) {
        if (i == 0) {
            m_tangent_y[i] = closed ? 0.5f * (m_y[1] - m_y[count - 2]) : 0.5f * (m_y[1] - m_y[0]);
        } else if (i == count - 1) {
            m_tangent_y[i] = closed ? m_tangent_y[0] : 0.5f * (m_y[i] - m_y[i - 1]);
        } else {
            m_tangent_y[i] = 0.5f * (m_y[i + 1] - m_y[i - 1]);
        }
    }
}

float RorSpline::interpolate_y(float t) const {
    if (m_y.empty()) {
        return 0.0f;
    }
    const float segment = t * static_cast<float>(m_y.size() - 1);
    const unsigned index = static_cast<unsigned>(segment);
    t = segment - static_cast<float>(index);
    if (index + 1 >= m_y.size()) {
        return m_y[std::min<size_t>(index, m_y.size() - 1)];
    }
    if (t == 0.0f) {
        return m_y[index];
    }
    if (t == 1.0f) {
        return m_y[index + 1];
    }
    // Ogre's Hermite basis, powers (t^3, t^2, t, 1) times its coefficient matrix.
    const float t2 = t * t;
    const float t3 = t2 * t;
    const float h00 = 2.0f * t3 - 3.0f * t2 + 1.0f;
    const float h01 = -2.0f * t3 + 3.0f * t2;
    const float h10 = t3 - 2.0f * t2 + t;
    const float h11 = t3 - t2;
    return h00 * m_y[index] + h01 * m_y[index + 1] + h10 * m_tangent_y[index] + h11 * m_tangent_y[index + 1];
}

void RorKeyInertia::configure(float start_delay, float stop_delay, const RorSpline *start, const RorSpline *stop) {
    // Upstream keeps the previous delay when a new one is not positive.
    if (start_delay > 0.0f) {
        m_start_delay = start_delay;
    }
    if (stop_delay > 0.0f) {
        m_stop_delay = stop_delay;
    }
    if (start != nullptr) {
        m_start = start;
    }
    if (stop != nullptr) {
        m_stop = stop;
    }
}

float RorKeyInertia::calc(float input, float dt) {
    if (!active()) {
        return input;
    }
    float output = m_last_output;
    const float last = m_last_output;
    // Rising or falling in magnitude picks the curve; the sign of the difference the direction.
    const float rel_diff = std::fabs(input) - std::fabs(last);
    const float abs_diff = input - last;
    if (std::fabs(abs_diff) < 0.002f) {
        m_time = 0.0f;
    }
    m_time += dt;
    const float start_factor = std::min(m_start_delay * m_time, 1.0f);
    const float stop_factor = std::min(m_stop_delay * m_time, 1.0f);
    if (abs_diff > 0.0f) {
        if (rel_diff > 0.0f) {
            output = last + m_start->interpolate_y(start_factor) * 0.001f;
        }
        if (rel_diff < 0.0f) {
            output = last + m_stop->interpolate_y(stop_factor) * 0.001f;
        }
        if (output > input) {
            output = input;
        }
    }
    if (abs_diff < 0.0f) {
        if (rel_diff > 0.0f) {
            output = last - m_start->interpolate_y(start_factor) * 0.001f;
        }
        if (rel_diff < 0.0f) {
            output = last - m_stop->interpolate_y(stop_factor) * 0.001f;
        }
        if (output < input) {
            output = input;
        }
    }
    m_last_output = output;
    return output;
}

} // namespace rorgd
