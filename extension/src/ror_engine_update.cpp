// Upstream's `Engine::UpdateEngine` (gameplay/Engine.cpp), statement for statement: the turbo pass,
// the torque balance and the starter, the clutch, then in the automatic and semi-automatic modes
// the shift timing and the auto clutch, and once a frame the automatic box's gear choice.
#include "ror_approx.h"
#include "ror_drivetrain.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

namespace {
constexpr float RAD_PER_SEC_TO_RPM = 9.5492965855137f;
} // namespace

void RorDrivetrain::step(float dt, float wheel_rpm, bool do_update, const RorEngineActor &actor) {
    if (m_num_gears == 0 || dt <= 0.0f) {
        return;
    }
    m_cur_wheel_revolutions = wheel_rpm;
    float acc = m_cur_acc;
    acc = std::max(idle_mixture(), acc);
    acc = std::max(prime_mixture(), acc);

    m_turbo.update(dt, acc, m_cur_acc, m_cur_engine_rpm, m_engine_max_rpm, m_engine_is_running);

    // update engine speed
    float totaltorque = 0.0f;
    // engine braking
    if (m_engine_is_running && m_contact) {
        totaltorque += m_braking_torque * m_cur_engine_rpm / m_engine_max_rpm * (1.0f - m_cur_acc);
    } else if (!m_contact || !m_starter) {
        totaltorque += m_braking_torque;
    }
    // braking by hydropump
    if (m_cur_engine_rpm > 100.0f) {
        totaltorque -= 8.0f * m_hydropump_state / (m_cur_engine_rpm * 0.105f * dt);
    }
    if (m_engine_is_running && m_contact && m_cur_engine_rpm < (m_engine_max_rpm * 1.25f)) {
        m_cur_engine_torque = engine_power(m_cur_engine_rpm) * acc;
        totaltorque += m_cur_engine_torque;
    }
    // engine stall
    if (!m_engine_is_electric) {
        if (m_engine_is_running && m_cur_engine_rpm < m_engine_stall_rpm) {
            stop_engine();
        }
    }
    // engine start
    if (m_contact && !m_engine_is_running) {
        if (m_engine_is_electric) {
            if (m_starter) {
                m_engine_is_running = true;
            }
        } else {
            if (m_cur_engine_rpm < m_engine_idle_rpm) {
                if (m_starter) {
                    totaltorque += m_engine_torque * std::exp(-2.7f * m_cur_engine_rpm / m_engine_idle_rpm) - m_braking_torque;
                }
            } else {
                m_engine_is_running = true;
            }
        }
    }
    // clutch
    if (m_cur_gear) {
        totaltorque -= m_cur_clutch_torque / m_gear_ratios[static_cast<size_t>(m_cur_gear + 1)];
    }
    // integration
    m_cur_engine_rpm += dt * totaltorque / m_engine_inertia;
    // update clutch torque
    if (m_cur_gear) {
        const float force_threshold = 1.5f * std::max(m_engine_torque, engine_power(m_cur_engine_rpm)) * std::abs(m_gear_ratios[2]);
        const float gearboxspinner = m_cur_engine_rpm / m_gear_ratios[static_cast<size_t>(m_cur_gear + 1)];
        m_cur_clutch_torque = (gearboxspinner - m_cur_wheel_revolutions) * m_cur_clutch * m_clutch_force;
        m_cur_clutch_torque = std::clamp(m_cur_clutch_torque, -force_threshold, +force_threshold);
        m_cur_clutch_torque *= 1.0f - approx_exp(-std::abs(gearboxspinner - m_cur_wheel_revolutions));
    } else {
        m_cur_clutch_torque = 0.0f;
    }
    m_cur_engine_rpm = std::max(0.0f, m_cur_engine_rpm);

    if (m_auto_mode < MANUAL) {
        // auto-shift
        if (m_shifting) {
            m_shift_clock += dt;
            if (m_shift_val) {
                const float declutch_time = std::min(m_shift_time - m_clutch_time, m_clutch_time);
                if (m_shift_clock <= declutch_time) {
                    // depress the clutch
                    const float ratio = std::pow(1.0f - (m_shift_clock / declutch_time), 2);
                    m_cur_clutch = std::min(ratio, m_cur_clutch);
                    m_cur_acc = std::min(ratio, m_auto_cur_acc);
                } else {
                    // engage a gear
                    if (m_autoselect != NEUTRAL) {
                        m_cur_gear += m_shift_val;
                        m_cur_gear = std::max(-1, m_cur_gear);
                        m_cur_gear = std::min(m_cur_gear, m_num_gears);
                    }
                    m_shift_val = 0;
                }
            }
            if (m_shift_clock > m_shift_time) {
                // done shifting
                m_cur_acc = m_auto_cur_acc;
                m_shifting = 0;
                m_post_shifting = 1;
                m_post_shift_clock = 0.0f;
            } else if (!m_shift_val && m_cur_gear && m_shift_clock >= (m_shift_time - m_clutch_time)) {
                // release the clutch
                const float timer = m_shift_clock - (m_shift_time - m_clutch_time);
                const float ratio = std::sqrt(timer / m_clutch_time);
                m_cur_acc = (m_auto_cur_acc / 2.0f) * ratio;
            }
        }
        if (m_post_shifting) {
            m_post_shift_clock += dt;
            if (m_post_shift_clock > m_post_shift_time) {
                m_post_shifting = 0;
            } else if (m_auto_cur_acc > 0.0f) {
                const float ratio = m_post_shift_clock / m_post_shift_time;
                m_cur_acc = (m_auto_cur_acc / 2.0f) + (m_auto_cur_acc / 2.0f) * ratio;
            } else if (m_cur_gear) {
                const float gearboxspinner = m_cur_engine_rpm / m_gear_ratios[static_cast<size_t>(m_cur_gear + 1)];
                if (m_cur_wheel_revolutions > gearboxspinner) {
                    const float ratio = std::sqrt(m_post_shift_clock / m_post_shift_time);
                    m_cur_clutch = std::max(m_cur_clutch, ratio);
                }
            }
        }
        // auto clutch
        const float declutch_rpm = m_engine_min_rpm * 0.75f + m_engine_stall_rpm * 0.25f;
        if (m_cur_gear == 0 || m_cur_engine_rpm < declutch_rpm) {
            m_cur_clutch = 0.0f;
        } else if (m_cur_engine_rpm < m_engine_min_rpm && m_engine_min_rpm > declutch_rpm) {
            const float clutch = (m_cur_engine_rpm - declutch_rpm) / (m_engine_min_rpm - declutch_rpm);
            m_cur_clutch = std::min(clutch * clutch, m_cur_clutch);
        } else if (!m_shift_val && m_cur_engine_rpm > m_engine_min_rpm && m_cur_clutch < 1.0f) {
            const float threshold = 1.5f * engine_power(m_cur_engine_rpm) * std::abs(m_gear_ratios[2]);
            const float gearboxspinner = m_cur_engine_rpm / m_gear_ratios[static_cast<size_t>(m_cur_gear + 1)];
            const float clutch_torque = (gearboxspinner - m_cur_wheel_revolutions) * m_clutch_force;
            const float re_torque = std::clamp(clutch_torque, -threshold, +threshold) / m_gear_ratios[static_cast<size_t>(m_cur_gear + 1)];
            const float range = (m_engine_max_rpm - m_engine_min_rpm) * 0.4f * std::sqrt(std::max(0.2f, acc));
            const float power_ratio = std::min((m_cur_engine_rpm - m_engine_min_rpm) / range, 1.0f);
            const float engine_torque = engine_power(m_cur_engine_rpm) * std::min(m_cur_acc, 0.9f) * power_ratio;
            const float torque_diff = std::min(engine_torque, std::abs(re_torque));
            const float clutch = torque_diff / re_torque;
            m_cur_clutch = std::max(m_cur_clutch, clutch);
        }
        m_cur_clutch = std::max(0.0f, m_cur_clutch);
        m_cur_clutch = std::min(m_cur_clutch, 1.0f);
    }

    if (do_update && !m_shifting && !m_post_shifting) {
        update_auto_shift(acc, actor);
    }
}

// The once-a-frame half of `UpdateEngine`: the "gear hack" reference speed, then in automatic
// DRIVE or TWO upstream's shift choice from the last 50 and 200 frames of rpm, throttle and brake,
// and in the automatic and semi-automatic modes the guard against over-revving.
void RorDrivetrain::update_auto_shift(float acc, const RorEngineActor &actor) {
    float velocity = static_cast<float>(actor.node0_velocity.length());
    const godot::Vector3 hdir = actor.camera_dir;
    if (hdir != godot::Vector3()) {
        velocity = static_cast<float>(hdir.dot(actor.node0_velocity));
    }
    if (actor.wheel0_radius != 0) {
        m_ref_wheel_revolutions = velocity / actor.wheel0_radius * RAD_PER_SEC_TO_RPM;
    }
    const auto ratio = [this](int index) { return m_gear_ratios[static_cast<size_t>(index)]; };
    if (!m_engine_is_electric && m_auto_mode == AUTO && (m_autoselect == DRIVE || m_autoselect == TWO) && m_cur_gear > 0) {
        if ((m_cur_engine_rpm > m_engine_max_rpm - 100.0f && m_cur_gear > 1) ||
            m_cur_wheel_revolutions * ratio(m_cur_gear + 1) > m_engine_max_rpm - 100.0f) {
            if ((m_autoselect == DRIVE && m_cur_gear < m_num_gears && m_cur_clutch > 0.99f) ||
                (m_autoselect == TWO && m_cur_gear < std::min(2, m_num_gears))) {
                m_kickdown_delay_counter = 100;
                shift(1);
            }
        } else if (m_cur_gear > 1 && m_ref_wheel_revolutions * ratio(m_cur_gear) < m_engine_max_rpm &&
                   (m_cur_engine_rpm < m_engine_min_rpm ||
                    (m_cur_engine_rpm < m_engine_min_rpm + m_shift_behaviour * m_half_rpm_range / 2.0f &&
                     engine_power(m_cur_wheel_revolutions * ratio(m_cur_gear)) >
                             engine_power(m_cur_wheel_revolutions * ratio(m_cur_gear + 1))))) {
            shift(-1);
        }

        int new_gear = m_cur_gear;
        m_rpms.push_front(m_cur_engine_rpm);
        m_accs.push_front(acc);
        m_brakes.push_front(actor.brake);

        float avg_rpm50 = 0.0f, avg_rpm200 = 0.0f, avg_acc50 = 0.0f, avg_acc200 = 0.0f, avg_brake50 = 0.0f, avg_brake200 = 0.0f;
        for (unsigned int i = 0; i < m_accs.size(); i++) {
            if (i < 50) {
                avg_rpm50 += m_rpms[i];
                avg_acc50 += m_accs[i];
                avg_brake50 += m_brakes[i];
            }
            avg_rpm200 += m_rpms[i];
            avg_acc200 += m_accs[i];
            avg_brake200 += m_brakes[i];
        }
        avg_rpm50 /= std::min(m_rpms.size(), (std::deque<float>::size_type)50);
        avg_acc50 /= std::min(m_accs.size(), (std::deque<float>::size_type)50);
        avg_brake50 /= std::min(m_brakes.size(), (std::deque<float>::size_type)50);
        avg_rpm200 /= m_rpms.size();
        avg_acc200 /= m_accs.size();
        avg_brake200 /= m_brakes.size();

        if (avg_acc50 > 0.8f || avg_acc200 > 0.8f || avg_brake50 > 0.8f || avg_brake200 > 0.8f) {
            m_shift_behaviour = std::min(m_shift_behaviour + 0.01f, 1.0f);
        } else if (acc < 0.5f && avg_acc50 < 0.5f && avg_acc200 < 0.5f && actor.brake < 0.5f && avg_brake50 < 0.5f &&
                   avg_brake200 < 0.5) {
            m_shift_behaviour /= 1.01;
        }

        const auto pulls_harder = [&](int g) {
            return engine_power(m_cur_wheel_revolutions * ratio(g)) * ratio(g) >
                   engine_power(m_cur_wheel_revolutions * ratio(g + 1)) * ratio(g + 1);
        };
        if (avg_acc50 > 0.8f && m_cur_engine_rpm < m_engine_max_rpm - m_one_third_rpm_range) {
            while (new_gear > 1 && m_cur_wheel_revolutions * ratio(new_gear) < m_engine_max_rpm - m_one_third_rpm_range &&
                   pulls_harder(new_gear)) {
                new_gear--;
            }
        } else if (avg_acc50 > 0.6f && acc < 0.8f && acc > avg_acc50 + 0.1f && m_cur_engine_rpm < m_engine_min_rpm + m_half_rpm_range) {
            if (new_gear > 1 && m_cur_wheel_revolutions * ratio(new_gear) < m_engine_min_rpm + m_half_rpm_range && pulls_harder(new_gear)) {
                new_gear--;
            }
        } else if (avg_acc50 > 0.4f && acc < 0.8f && acc > avg_acc50 + 0.1f && m_cur_engine_rpm < m_engine_min_rpm + m_half_rpm_range) {
            if (new_gear > 1 && m_cur_wheel_revolutions * ratio(new_gear) < m_engine_min_rpm + m_one_third_rpm_range &&
                pulls_harder(new_gear)) {
                new_gear--;
            }
        } else if (m_cur_gear < (m_autoselect == TWO ? std::min(2, m_num_gears) : m_num_gears) && avg_brake200 < 0.2f &&
                   acc < std::min(avg_acc200 + 0.1f, 1.0f) && m_cur_engine_rpm > avg_rpm200 - m_full_rpm_range / 20.0f) {
            if (avg_acc200 < 0.6f && avg_acc200 > 0.4f && m_cur_engine_rpm > m_engine_min_rpm + m_one_third_rpm_range &&
                m_cur_engine_rpm < m_engine_max_rpm - m_one_third_rpm_range) {
                if (m_cur_wheel_revolutions * ratio(new_gear + 2) > m_engine_min_rpm + m_one_third_rpm_range) {
                    new_gear++;
                }
            } else if (avg_acc200 < 0.4f && avg_acc200 > 0.2f && m_cur_engine_rpm > m_engine_min_rpm + m_one_third_rpm_range) {
                if (m_cur_wheel_revolutions * ratio(new_gear + 2) > m_engine_min_rpm + m_one_third_rpm_range / 2.0f) {
                    new_gear++;
                }
            } else if (avg_acc200 < 0.2f && m_cur_engine_rpm > m_engine_min_rpm + m_one_third_rpm_range / 2.0f &&
                       m_cur_engine_rpm < m_engine_min_rpm + m_half_rpm_range) {
                if (m_cur_wheel_revolutions * ratio(new_gear + 2) > m_engine_min_rpm + m_one_third_rpm_range / 2.0f) {
                    new_gear++;
                }
            }
            if (new_gear > m_cur_gear) {
                m_upshift_delay_counter++;
                if (m_upshift_delay_counter <= 100 * m_shift_behaviour) {
                    new_gear = m_cur_gear;
                }
            } else {
                m_upshift_delay_counter = 0;
            }
        }

        if (new_gear < m_cur_gear && m_kickdown_delay_counter > 0) {
            new_gear = m_cur_gear;
        }
        m_kickdown_delay_counter = std::max(0, m_kickdown_delay_counter - 1);

        if ((new_gear < m_cur_gear &&
             std::abs(m_cur_wheel_revolutions * (ratio(new_gear + 1) - ratio(m_cur_gear + 1))) > m_one_third_rpm_range / 6.0f) ||
            (new_gear > m_cur_gear &&
             std::abs(m_cur_wheel_revolutions * (ratio(new_gear + 1) - ratio(m_cur_gear + 1))) > m_one_third_rpm_range / 3.0f)) {
            if (std::abs(actor.gforce_y) < 0.25f) {
                shift_to(new_gear);
            }
        }

        if (m_accs.size() > 200) {
            m_rpms.pop_back();
            m_accs.pop_back();
            m_brakes.pop_back();
        }
        // avoid over-revving
        if (m_auto_mode <= SEMI_AUTO && m_cur_gear != 0) {
            if (std::abs(m_cur_wheel_revolutions * ratio(m_cur_gear + 1)) > m_engine_max_rpm * 1.25f) {
                const float clutch = 0.0f + 1.0f / (1.0f + std::abs(m_cur_wheel_revolutions * ratio(m_cur_gear + 1) - m_engine_max_rpm * 1.25f) / 2.0f);
                m_cur_clutch = std::min(clutch, m_cur_clutch);
            }
            if (m_cur_gear * m_cur_wheel_revolutions < -10.0f) {
                const float clutch = 0.0f + 1.0f / (1.0f + std::abs(-10.0f - m_cur_gear * m_cur_wheel_revolutions) / 2.0f);
                m_cur_clutch = std::min(clutch, m_cur_clutch);
            }
        }
    }
}

} // namespace rorgd
