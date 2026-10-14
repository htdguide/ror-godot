#include "ror_drivetrain.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

namespace {
// Ogre 1.11's `SimpleSpline` Hermite matrix, row by row.
constexpr float SPLINE_COEFFS[4][4] = {{2, -2, 1, 1}, {-3, 3, -2, -1}, {0, 0, 1, 0}, {1, 0, 0, 0}};
} // namespace

// Upstream's constructor: the idle capped at 800 rpm, the engine braking a fifth of the torque,
// the gear vector [R|N|1...] at the crank, the rpm ranges the automatic box reasons with.
void RorDrivetrain::configure(float min_rpm, float max_rpm, float torque, float diff_ratio, float reverse_gear,
                              float neutral_gear, const std::vector<float> &forward_gears) {
    m_engine_min_rpm = std::abs(min_rpm);
    m_engine_max_rpm = std::abs(max_rpm);
    m_engine_torque = torque;
    m_engine_idle_rpm = std::min(std::abs(min_rpm), 800.0f);
    m_braking_torque = -torque / 5.0f;
    m_diff_ratio = diff_ratio;
    m_tcase_ratio = 1.0f;
    m_num_gears = static_cast<int>(forward_gears.size());
    m_full_rpm_range = (m_engine_max_rpm - m_engine_min_rpm);
    m_one_third_rpm_range = m_full_rpm_range / 3.0f;
    m_half_rpm_range = m_full_rpm_range / 2.0f;
    m_gear_ratios.clear();
    m_gear_ratios.push_back(-reverse_gear * diff_ratio);
    m_gear_ratios.push_back(neutral_gear * diff_ratio);
    for (float gear : forward_gears) {
        m_gear_ratios.push_back(gear * diff_ratio);
    }
}

void RorDrivetrain::set_options(float inertia, char type, float clutch_force, float clutch_time, float shift_time,
                                float post_shift_time, float idle_rpm, float stall_rpm, float braking_torque,
                                float max_idle_mixture, float min_idle_mixture) {
    m_engine_inertia = inertia;
    m_clutch_force = clutch_force;
    if (clutch_time > 0) {
        m_clutch_time = clutch_time;
    }
    if (shift_time > 0) {
        m_shift_time = shift_time;
    }
    if (post_shift_time > 0) {
        m_post_shift_time = post_shift_time;
    }
    if (idle_rpm > 0) {
        m_engine_idle_rpm = idle_rpm;
    }
    if (stall_rpm > 0) {
        m_engine_stall_rpm = stall_rpm;
    }
    if (max_idle_mixture > 0) {
        m_max_idle_mixture = max_idle_mixture;
    }
    if (min_idle_mixture > 0) {
        m_min_idle_mixture = min_idle_mixture;
    }
    if (braking_torque > 0) {
        m_braking_torque = -braking_torque;
    }
    m_shift_time = std::max(0.0f, m_shift_time);
    m_post_shift_time = std::max(0.0f, m_post_shift_time);
    m_clutch_time = std::clamp(m_clutch_time, 0.0f, 0.9f * m_shift_time);
    m_engine_stall_rpm = std::clamp(m_engine_stall_rpm, 0.0f, 0.9f * m_engine_idle_rpm);
    // A car ('c') or an electric motor ('e') has no `OLD` turbo, and a lighter default clutch.
    m_turbo.old_mode = !(type == 'c' || type == 'e');
    m_engine_is_electric = type == 'e';
    if (m_clutch_force < 0.0f) {
        m_clutch_force = (type == 'c' || type == 'e') ? 5000.0f : 10000.0f;
    }
}

// Upstream's spline: each point added at (rpm, ratio, 0), the tangents recalculated as Ogre's
// `recalcTangents` does (a closed curve when the first point is the last).
void RorDrivetrain::set_torque_curve(const std::vector<float> &rpm, const std::vector<float> &ratio) {
    const size_t count = std::min(rpm.size(), ratio.size());
    m_curve_x.assign(rpm.begin(), rpm.begin() + count);
    m_curve_y.assign(ratio.begin(), ratio.begin() + count);
    m_curve_tangent_y.assign(count, 0.0f);
    if (count < 2) {
        return;
    }
    const bool closed = m_curve_x[0] == m_curve_x[count - 1] && m_curve_y[0] == m_curve_y[count - 1];
    for (size_t i = 0; i < count; ++i) {
        if (i == 0) {
            m_curve_tangent_y[i] = 0.5f * (closed ? m_curve_y[1] - m_curve_y[count - 2] : m_curve_y[1] - m_curve_y[0]);
        } else if (i == count - 1) {
            m_curve_tangent_y[i] = 0.5f * (closed ? m_curve_y[1] - m_curve_y[i - 1] : m_curve_y[i] - m_curve_y[i - 1]);
        } else {
            m_curve_tangent_y[i] = 0.5f * (m_curve_y[i + 1] - m_curve_y[i - 1]);
        }
    }
}

// Upstream's `TorqueCurve::getEngineTorque` through `SimpleSpline::interpolate`: the rpm mapped
// onto the curve's own span, then the segment by index, then `powers * mCoeffs * pt` as Ogre's
// Vector4-by-Matrix4 products sum them. With no curve, upstream's default model.
float RorDrivetrain::torque_curve(float rpm) const {
    const size_t count = m_curve_y.size();
    if (count == 0) {
        return 1.0f;
    }
    if (count == 1) {
        return m_curve_y[0];
    }
    const float min_rpm = m_curve_x[0];
    const float max_rpm = m_curve_x[count - 1];
    if (min_rpm == max_rpm) {
        return m_curve_y[0];
    }
    float t = std::clamp((rpm - min_rpm) / (max_rpm - min_rpm), 0.0f, 1.0f);
    const float seg = t * static_cast<float>(count - 1);
    const unsigned int index = static_cast<unsigned int>(seg);
    t = seg - index;
    if (index + 1 == count) {
        return m_curve_y[index];
    }
    if (t == 0.0f) {
        return m_curve_y[index];
    }
    if (t == 1.0f) {
        return m_curve_y[index + 1];
    }
    const float t2 = t * t;
    const float t3 = t2 * t;
    const float powers[4] = {t3, t2, t, 1};
    float b[4];
    for (int j = 0; j < 4; ++j) {
        b[j] = powers[0] * SPLINE_COEFFS[0][j] + powers[1] * SPLINE_COEFFS[1][j] + powers[2] * SPLINE_COEFFS[2][j] +
               powers[3] * SPLINE_COEFFS[3][j];
    }
    return b[0] * m_curve_y[index] + b[1] * m_curve_y[index + 1] + b[2] * m_curve_tangent_y[index] +
           b[3] * m_curve_tangent_y[index + 1];
}

float RorDrivetrain::engine_power(float rpm) const {
    return (m_engine_torque * torque_curve(rpm)) + m_turbo.power(m_engine_torque);
}

float RorDrivetrain::acc_to_hold_rpm() const {
    return (-m_braking_torque * std::pow(m_cur_engine_rpm / m_engine_max_rpm, 2.0f)) / engine_power(m_cur_engine_rpm);
}

void RorDrivetrain::set_contact(bool contact) {
    m_contact = contact;
}

void RorDrivetrain::auto_set_acc(float acc) {
    m_auto_cur_acc = acc;
    if (!m_shifting) {
        m_cur_acc = acc;
    }
}

void RorDrivetrain::set_selector(int selector) {
    selector = std::max(-1, std::min(1, selector));
    if (m_auto_mode == AUTO) {
        auto_shift_set(selector < 0 ? REAR : (selector == 0 ? NEUTRAL : DRIVE));
    } else {
        shift_to(selector);
    }
}

// Upstream's `startEngine`, which begins with `offStart`.
void RorDrivetrain::start() {
    stop();
    m_contact = true;
    m_cur_engine_rpm = m_engine_idle_rpm;
    m_engine_is_running = true;
    if (m_auto_mode <= SEMI_AUTO) {
        m_cur_gear = 1;
    }
    if (m_auto_mode == AUTO) {
        m_autoselect = DRIVE;
    }
}

void RorDrivetrain::stop() {
    m_autoselect = MANUALMODE;
    m_contact = false;
    m_cur_acc = 0.0f;
    m_cur_clutch = 0.0f;
    m_cur_clutch_torque = 0.0f;
    m_cur_engine_rpm = 0.0f;
    m_cur_gear = 0;
    m_post_shifting = 0;
    m_engine_is_running = false;
    m_shifting = 0;
    m_shift_val = 0;
    if (m_auto_mode == AUTO) {
        m_autoselect = NEUTRAL;
    }
    m_turbo.reset();
}

void RorDrivetrain::set_tcase_ratio(float ratio) {
    if (ratio < 1.0f) {
        return;
    }
    for (float &gear : m_gear_ratios) {
        gear /= m_tcase_ratio;
    }
    m_tcase_ratio = ratio;
    for (float &gear : m_gear_ratios) {
        gear *= m_tcase_ratio;
    }
}

float RorDrivetrain::ratio_of(int gear) const {
    return m_gear_ratios[static_cast<size_t>(gear + 1)];
}

float RorDrivetrain::crank_factor() const {
    const float min_working_rpm = m_engine_idle_rpm * 1.1f;
    float rpm_ratio = (m_cur_engine_rpm - min_working_rpm) / (m_engine_max_rpm - min_working_rpm);
    rpm_ratio = std::max(0.0f, rpm_ratio);
    rpm_ratio = std::min(rpm_ratio, 1.0f);
    return 5.0f * rpm_ratio;
}

float RorDrivetrain::idle_mixture() const {
    if (m_cur_engine_rpm <= m_engine_idle_rpm) {
        return m_max_idle_mixture;
    }
    return m_min_idle_mixture;
}

float RorDrivetrain::prime_mixture() const {
    if (m_engine_is_priming) {
        const float crankfactor = crank_factor();
        if (crankfactor < 0.9f) {
            return 1.0f;
        } else if (crankfactor < 1.0f) {
            return 10.0f * (1.0f - crankfactor);
        }
    }
    return 0.0f;
}

void RorDrivetrain::shift(int val) {
    if (!val || m_cur_gear + val < -1 || m_cur_gear + val > m_num_gears) {
        return;
    }
    if (m_auto_mode < MANUAL) {
        m_shift_val = val;
        m_shifting = 1;
        m_shift_clock = 0.0f;
    } else if (m_cur_clutch > 0.25f) {
        // A gear grinds rather than going in with the clutch engaged (upstream plays a sound).
    } else {
        m_cur_gear += val;
    }
}

void RorDrivetrain::toggle_auto_mode() {
    m_auto_mode = static_cast<Mode>((static_cast<int>(m_auto_mode) + 1) % (static_cast<int>(MANUAL_RANGES) + 1));
    if (m_auto_mode == AUTO) {
        if (m_cur_gear > 0) {
            m_autoselect = DRIVE;
        }
        if (m_cur_gear < 0) {
            m_autoselect = REAR;
        }
        if (m_cur_gear == 0) {
            m_autoselect = NEUTRAL;
        }
    } else {
        m_autoselect = MANUALMODE;
    }
    if (m_auto_mode == MANUAL_RANGES) {
        m_cur_gear_range = 0;
    }
}

void RorDrivetrain::update_shifts() {
    if (m_autoselect == MANUALMODE) {
        return;
    }
    if (m_autoselect == REAR) {
        m_cur_gear = -1;
    } else if (m_autoselect == NEUTRAL) {
        m_cur_gear = 0;
    } else if (m_autoselect == ONE) {
        m_cur_gear = 1;
    } else {
        int new_gear = 1;
        while (new_gear < m_num_gears && m_cur_wheel_revolutions > 0.0f &&
               m_cur_wheel_revolutions * m_gear_ratios[static_cast<size_t>(new_gear + 1)] > m_engine_max_rpm - 100.0f) {
            new_gear++;
        }
        m_cur_gear = new_gear;
        if (m_autoselect == TWO) {
            m_cur_gear = std::min(m_cur_gear, 2);
        }
    }
}

void RorDrivetrain::auto_shift_set(int mode) {
    m_autoselect = mode;
    if (m_engine_is_electric && m_autoselect > DRIVE) {
        m_autoselect = DRIVE;
    }
    update_shifts();
}

void RorDrivetrain::auto_shift_up() {
    if (m_autoselect != REAR) {
        m_autoselect = m_autoselect - 1;
        update_shifts();
    }
}

void RorDrivetrain::auto_shift_down() {
    if ((m_engine_is_electric && m_autoselect != DRIVE) || (!m_engine_is_electric && m_autoselect != ONE)) {
        m_autoselect = m_autoselect + 1;
        update_shifts();
    }
}

void RorDrivetrain::set_manual_clutch(float val) {
    if (m_auto_mode >= MANUAL) {
        val = std::max(0.0f, val);
        m_cur_clutch = 1.0 - val;
    }
}

} // namespace rorgd
