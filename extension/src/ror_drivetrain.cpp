#include "ror_drivetrain.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

namespace {
// Upstream caps the idle at 800 rpm however high a file's stated minimum is.
constexpr float IDLE_RPM_CAP = 800.0f;
// Above this multiple of the redline the engine stops making power.
constexpr float OVERREV_RATIO = 1.25f;
// Upstream shifts up and down around this much headroom below the redline.
constexpr float SHIFT_MARGIN_RPM = 100.0f;

float clampf(float value, float low, float high) {
    return std::fmax(low, std::fmin(high, value));
}
} // namespace

void RorDrivetrain::configure(float min_rpm, float max_rpm, float torque, float diff_ratio, float reverse_gear,
                              float neutral_gear, const std::vector<float> &forward_gears) {
    m_min_rpm = std::fabs(min_rpm);
    m_max_rpm = std::fabs(max_rpm);
    m_torque = torque;
    m_idle_rpm = std::fmin(std::fabs(min_rpm), IDLE_RPM_CAP);
    // Upstream's default, before `engoption` may lower it.
    m_braking_torque = -torque / 5.0f;
    m_gear_ratios.clear();
    m_gear_ratios.push_back(-reverse_gear * diff_ratio);
    m_gear_ratios.push_back(neutral_gear * diff_ratio);
    for (float gear : forward_gears) {
        m_gear_ratios.push_back(gear * diff_ratio);
    }
    m_gear_count = static_cast<int>(forward_gears.size());
    // A single flat point is the "default" torque model: full torque at every rpm. A
    // caller that knows better replaces it.
    if (m_curve_rpm.empty()) {
        set_torque_curve({0.0f, 10000.0f}, {1.0f, 1.0f});
    }
}

void RorDrivetrain::set_options(float inertia, char type, float clutch_force, float clutch_time, float shift_time,
                                float post_shift_time, float idle_rpm, float stall_rpm, float braking_torque) {
    m_inertia = inertia;
    m_clutch_force = clutch_force;
    if (clutch_time > 0.0f) {
        m_clutch_time = clutch_time;
    }
    if (shift_time > 0.0f) {
        m_shift_time = shift_time;
    }
    if (post_shift_time > 0.0f) {
        m_post_shift_time = post_shift_time;
    }
    if (idle_rpm > 0.0f) {
        m_idle_rpm = idle_rpm;
    }
    if (stall_rpm > 0.0f) {
        m_stall_rpm = stall_rpm;
    }
    if (braking_torque > 0.0f) {
        m_braking_torque = -braking_torque;
    }
    m_shift_time = std::fmax(0.0f, m_shift_time);
    m_post_shift_time = std::fmax(0.0f, m_post_shift_time);
    m_clutch_time = clampf(m_clutch_time, 0.0f, 0.9f * m_shift_time);
    m_stall_rpm = clampf(m_stall_rpm, 0.0f, 0.9f * m_idle_rpm);
    // A car or an electric motor gets a lighter default clutch than a lorry.
    if (m_clutch_force < 0.0f) {
        m_clutch_force = (type == 'c' || type == 'e') ? 5000.0f : 10000.0f;
    }
}

// Catmull-Rom tangents, matching the Ogre spline upstream reads the curve through: the
// interior tangents are the central difference, the ends the one-sided one. Interpolating
// linearly instead would put this curve a few percent away from upstream's at every rpm
// between two stated points, which is the kind of quiet difference that makes a
// comparison against upstream meaningless.
void RorDrivetrain::set_torque_curve(const std::vector<float> &rpm, const std::vector<float> &ratio) {
    const size_t count = std::min(rpm.size(), ratio.size());
    m_curve_rpm.assign(rpm.begin(), rpm.begin() + count);
    m_curve_ratio.assign(ratio.begin(), ratio.begin() + count);
    m_curve_tangent.assign(count, 0.0f);
    if (count < 2) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        if (i == 0) {
            m_curve_tangent[i] = 0.5f * (m_curve_ratio[1] - m_curve_ratio[0]);
        } else if (i + 1 == count) {
            m_curve_tangent[i] = 0.5f * (m_curve_ratio[i] - m_curve_ratio[i - 1]);
        } else {
            m_curve_tangent[i] = 0.5f * (m_curve_ratio[i + 1] - m_curve_ratio[i - 1]);
        }
    }
}

// Upstream maps rpm onto the curve by its own span, not by looking up the x values, then
// walks the spline by segment index. Two stated points either side of a gap are therefore
// the same distance apart in the parameter whatever their rpm says, which is only exact
// when the points are evenly spaced — and upstream's models are.
float RorDrivetrain::engine_power(float rpm) const {
    const size_t count = m_curve_ratio.size();
    if (count == 0) {
        return m_torque;
    }
    if (count == 1) {
        return m_torque * m_curve_ratio[0];
    }
    const float low = m_curve_rpm.front();
    const float high = m_curve_rpm.back();
    if (low == high) {
        return m_torque * m_curve_ratio[0];
    }
    const float span = clampf((rpm - low) / (high - low), 0.0f, 1.0f) * static_cast<float>(count - 1);
    size_t segment = static_cast<size_t>(span);
    if (segment + 1 >= count) {
        return m_torque * m_curve_ratio[count - 1];
    }
    const float t = span - static_cast<float>(segment);
    const float t2 = t * t;
    const float t3 = t2 * t;
    const float value = (2.0f * t3 - 3.0f * t2 + 1.0f) * m_curve_ratio[segment] +
            (-2.0f * t3 + 3.0f * t2) * m_curve_ratio[segment + 1] +
            (t3 - 2.0f * t2 + t) * m_curve_tangent[segment] + (t3 - t2) * m_curve_tangent[segment + 1];
    return m_torque * value;
}

void RorDrivetrain::set_contact(bool contact) {
    m_contact = contact;
}

void RorDrivetrain::set_starter(bool starter) {
    m_starter = starter;
}

void RorDrivetrain::set_throttle(float acc) {
    m_commanded_acc = clampf(acc, 0.0f, 1.0f);
}

void RorDrivetrain::set_selector(int selector) {
    m_selector = std::max(-1, std::min(1, selector));
    if (m_selector == -1) {
        m_gear = -1;
    } else if (m_selector == 0) {
        m_gear = 0;
    } else if (m_gear <= 0) {
        m_gear = 1;
    }
}

void RorDrivetrain::start() {
    m_contact = true;
    m_running = true;
    m_rpm = m_idle_rpm;
}

void RorDrivetrain::stop() {
    m_running = false;
    m_contact = false;
    m_rpm = 0.0f;
    m_clutch = 0.0f;
    m_clutch_torque = 0.0f;
}

float RorDrivetrain::ratio_of(int gear) const {
    const size_t index = static_cast<size_t>(gear + 1);
    if (index >= m_gear_ratios.size()) {
        return 1.0f;
    }
    return m_gear_ratios[index];
}

float RorDrivetrain::idle_mixture() const {
    return m_rpm <= m_idle_rpm ? m_max_idle_mixture : m_min_idle_mixture;
}

void RorDrivetrain::step(float dt, float wheel_rpm, bool do_update) {
    if (m_gear_count == 0 || dt <= 0.0f) {
        return;
    }
    m_wheel_rpm = wheel_rpm;
    m_acc = m_commanded_acc;
    // Idling is a throttle floor, not a special case: it is why an engine in gear at rest
    // creeps forward instead of stalling the moment the driver lifts off.
    const float acc = std::fmax(idle_mixture(), m_acc);

    float total_torque = 0.0f;
    if (m_running && m_contact) {
        total_torque += m_braking_torque * m_rpm / m_max_rpm * (1.0f - m_acc);
    } else if (!m_contact || !m_starter) {
        total_torque += m_braking_torque;
    }
    if (m_running && m_contact && m_rpm < m_max_rpm * OVERREV_RATIO) {
        total_torque += engine_power(m_rpm) * acc;
    }
    if (m_running && m_rpm < m_stall_rpm) {
        m_running = false;
    }
    if (m_contact && !m_running) {
        if (m_rpm < m_idle_rpm) {
            if (m_starter) {
                total_torque += m_torque * std::exp(-2.7f * m_rpm / m_idle_rpm) - m_braking_torque;
            }
        } else {
            m_running = true;
        }
    }
    if (m_gear != 0) {
        total_torque -= m_clutch_torque / ratio_of(m_gear);
    }

    m_rpm += dt * total_torque / m_inertia;

    if (m_gear != 0) {
        const float threshold = 1.5f * std::fmax(m_torque, engine_power(m_rpm)) * std::fabs(ratio_of(1));
        const float gearbox_rpm = m_rpm / ratio_of(m_gear);
        m_clutch_torque = (gearbox_rpm - m_wheel_rpm) * m_clutch * m_clutch_force;
        m_clutch_torque = clampf(m_clutch_torque, -threshold, threshold);
        // Smoothed at the point the two sides meet, so the integrator is not handed a
        // step change in torque the instant the clutch locks up.
        m_clutch_torque *= 1.0f - std::exp(-std::fabs(gearbox_rpm - m_wheel_rpm));
    } else {
        m_clutch_torque = 0.0f;
    }
    m_rpm = std::fmax(0.0f, m_rpm);

    update_gear_choice(dt);
    update_auto_clutch(acc);
    if (do_update && !m_shifting && !m_post_shifting && m_selector > 0 && m_gear > 0) {
        const float gearbox_rpm = m_wheel_rpm * ratio_of(m_gear);
        if ((m_rpm > m_max_rpm - SHIFT_MARGIN_RPM && m_gear > 1) || gearbox_rpm > m_max_rpm - SHIFT_MARGIN_RPM) {
            if (m_gear < m_gear_count && m_clutch > 0.99f) {
                shift(1);
            }
        } else if (m_gear > 1 && m_wheel_rpm * ratio_of(m_gear - 1) < m_max_rpm && m_rpm < m_min_rpm) {
            shift(-1);
        }
    }
}

void RorDrivetrain::shift(int by) {
    if (by == 0) {
        return;
    }
    m_shifting = 1;
    m_shift_val = by;
    m_shift_clock = 0.0f;
}

// Upstream's shift timing: the clutch is let out, the gear changes at the halfway point,
// and the clutch comes back over the remainder. Without it a gear change teleports the
// engine speed and the rig lurches.
void RorDrivetrain::update_gear_choice(float dt) {
    if (m_shifting) {
        m_shift_clock += dt;
        if (m_shift_val != 0) {
            const float declutch_time = std::fmin(m_shift_time - m_clutch_time, m_clutch_time);
            if (declutch_time > 0.0f && m_shift_clock <= declutch_time) {
                const float ratio = 1.0f - (m_shift_clock / declutch_time);
                m_clutch = std::fmin(ratio * ratio, m_clutch);
                m_acc = std::fmin(ratio * ratio, m_commanded_acc);
            } else {
                m_gear = std::max(-1, std::min(m_gear + m_shift_val, m_gear_count));
                m_shift_val = 0;
            }
        }
        if (m_shift_clock > m_shift_time) {
            m_shifting = 0;
            m_post_shifting = 1;
            m_post_shift_clock = 0.0f;
        }
    }
    if (m_post_shifting) {
        m_post_shift_clock += dt;
        if (m_post_shift_clock > m_post_shift_time) {
            m_post_shifting = 0;
        } else if (m_gear != 0 && m_post_shift_time > 0.0f) {
            const float gearbox_rpm = m_rpm / ratio_of(m_gear);
            if (m_wheel_rpm > gearbox_rpm) {
                m_clutch = std::fmax(m_clutch, std::sqrt(m_post_shift_clock / m_post_shift_time));
            }
        }
    }
}

// Upstream's automatic clutch. Fully out below the declutch speed, feathered in over the
// approach to idle, and engaged only as far as the engine can actually pull: that last
// part is what makes a standing start work instead of either stalling or slipping for
// ever.
void RorDrivetrain::update_auto_clutch(float acc) {
    const float declutch_rpm = m_min_rpm * 0.75f + m_stall_rpm * 0.25f;
    if (m_gear == 0 || m_rpm < declutch_rpm) {
        m_clutch = 0.0f;
    } else if (m_rpm < m_min_rpm && m_min_rpm > declutch_rpm) {
        const float clutch = (m_rpm - declutch_rpm) / (m_min_rpm - declutch_rpm);
        m_clutch = std::fmin(clutch * clutch, m_clutch);
    } else if (m_shift_val == 0 && m_rpm > m_min_rpm && m_clutch < 1.0f) {
        const float threshold = 1.5f * engine_power(m_rpm) * std::fabs(ratio_of(1));
        const float gearbox_rpm = m_rpm / ratio_of(m_gear);
        const float raw = (gearbox_rpm - m_wheel_rpm) * m_clutch_force;
        const float reaction = clampf(raw, -threshold, threshold) / ratio_of(m_gear);
        const float range = (m_max_rpm - m_min_rpm) * 0.4f * std::sqrt(std::fmax(0.2f, acc));
        const float power_ratio = std::fmin((m_rpm - m_min_rpm) / range, 1.0f);
        const float available = engine_power(m_rpm) * std::fmin(m_acc, 0.9f) * power_ratio;
        if (reaction != 0.0f) {
            m_clutch = std::fmax(m_clutch, std::fmin(available, std::fabs(reaction)) / reaction);
        }
    }
    // Slip the clutch rather than let the wheels drive the engine past its limit.
    if (m_gear != 0) {
        const float gearbox_rpm = m_wheel_rpm * ratio_of(m_gear);
        if (std::fabs(gearbox_rpm) > m_max_rpm * OVERREV_RATIO) {
            const float clutch = 1.0f / (1.0f + std::fabs(gearbox_rpm - m_max_rpm * OVERREV_RATIO) / 2.0f);
            m_clutch = std::fmin(clutch, m_clutch);
        }
        if (static_cast<float>(m_gear) * m_wheel_rpm < -10.0f) {
            const float clutch = 1.0f / (1.0f + std::fabs(-10.0f - static_cast<float>(m_gear) * m_wheel_rpm) / 2.0f);
            m_clutch = std::fmin(clutch, m_clutch);
        }
    }
    m_clutch = clampf(m_clutch, 0.0f, 1.0f);
}

} // namespace rorgd
