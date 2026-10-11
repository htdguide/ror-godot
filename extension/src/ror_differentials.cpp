#include "ror_differentials.h"

#include "ror_wheels.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

void RorDifferential::split(float speed_a, float speed_b, float in, float dt, float &out_a, float &out_b) {
    if (types.empty()) {
        // Upstream returns without writing, and its caller then hands both sides zero.
        out_a = 0.0f;
        out_b = 0.0f;
        return;
    }
    switch (types[0]) {
    case DiffType::SPLIT:
        out_a = out_b = in / 2.0f;
        return;
    case DiffType::OPEN: {
        // Shared by wheel speed; at a crawl, evenly. Upstream's own note: it would need reaction
        // torque to be a real open differential.
        const float sum = std::fabs(speed_a) + std::fabs(speed_b);
        const float slowest = std::min(std::fabs(speed_a), std::fabs(speed_b));
        const float ratio = slowest > 1.0f ? std::fabs(speed_a) / sum : 0.5f;
        out_a = in * std::clamp(0.0f + ratio, 0.1f, 0.9f);
        out_b = in * std::clamp(1.0f - ratio, 0.1f, 0.9f);
        return;
    }
    case DiffType::VISCOUS: {
        const float damp = 10000.0f;
        const float delta_speed = speed_a - speed_b;
        out_a = in / 2.0f - delta_speed * damp;
        out_b = in / 2.0f + delta_speed * damp;
        return;
    }
    case DiffType::LOCKED: {
        // A torsion spring holding the two sides where they were when it locked, and its damper.
        const float rate = 1000000.0f;
        const float damp = rate / 100.0f;
        const float delta_speed = speed_a - speed_b;
        delta_rotation += delta_speed * dt;
        out_a = in / 2.0f - delta_rotation * rate - delta_speed * damp;
        out_b = in / 2.0f + delta_rotation * rate + delta_speed * damp;
        return;
    }
    }
}

void RorDifferential::toggle() {
    if (types.size() > 1) {
        std::rotate(types.begin(), types.begin() + 1, types.end());
    }
}

std::vector<DiffType> RorDifferentials::parse_types(const char *letters) {
    std::vector<DiffType> out;
    for (const char *c = letters; c != nullptr && *c != '\0'; ++c) {
        switch (*c) {
        case 's': out.push_back(DiffType::SPLIT); break;
        case 'o': out.push_back(DiffType::OPEN); break;
        case 'v': out.push_back(DiffType::VISCOUS); break;
        case 'l': out.push_back(DiffType::LOCKED); break;
        default: break;
        }
    }
    return out;
}

int RorDifferentials::add_axle(int wheel_a, int wheel_b, const std::vector<DiffType> &types) {
    RorDifferential diff;
    diff.a = wheel_a;
    diff.b = wheel_b;
    diff.types = types.empty() ? std::vector<DiffType>{DiffType::OPEN, DiffType::LOCKED} : types;
    m_wheel_diffs.push_back(diff);
    ++m_declared_axles;
    m_prepared = false;
    return static_cast<int>(m_wheel_diffs.size()) - 1;
}

int RorDifferentials::add_interaxle(int a, int b, const std::vector<DiffType> &types) {
    if (a == b || std::min(a, b) < 0 || std::max(a, b) >= static_cast<int>(m_wheel_diffs.size())) {
        return -1;
    }
    RorDifferential diff;
    diff.a = a;
    diff.b = b;
    diff.types = types.empty() ? std::vector<DiffType>{DiffType::LOCKED} : types;
    m_axle_diffs.push_back(diff);
    m_prepared = false;
    return static_cast<int>(m_axle_diffs.size()) - 1;
}

void RorDifferentials::prepare(const std::vector<RorWheel> &wheels) {
    if (m_prepared) {
        return;
    }
    m_prepared = true;
    if (m_wheel_diffs.empty()) {
        std::vector<int> driven;
        for (size_t i = 0; i < wheels.size(); ++i) {
            if (wheels[i].drive != WheelDrive::NONE) {
                driven.push_back(static_cast<int>(i));
            }
        }
        for (size_t i = 1; i < driven.size(); i += 2) {
            RorDifferential diff;
            diff.a = driven[i - 1];
            diff.b = driven[i];
            diff.types = {DiffType::VISCOUS};
            m_wheel_diffs.push_back(diff);
        }
    }
    if (m_axle_diffs.empty()) {
        for (size_t i = 1; i < m_wheel_diffs.size(); ++i) {
            RorDifferential diff;
            diff.a = static_cast<int>(i) - 1;
            diff.b = static_cast<int>(i);
            diff.types = {has_axles() ? DiffType::LOCKED : DiffType::VISCOUS};
            m_axle_diffs.push_back(diff);
        }
    }
}

void RorDifferentials::distribute(std::vector<RorWheel> &wheels, float dt) {
    const int count = static_cast<int>(wheels.size());
    auto valid = [count](const RorDifferential &d) {
        return d.a >= 0 && d.b >= 0 && d.a < count && d.b < count;
    };
    for (RorDifferential &diff : m_axle_diffs) {
        const RorDifferential &one = m_wheel_diffs[static_cast<size_t>(diff.a)];
        const RorDifferential &two = m_wheel_diffs[static_cast<size_t>(diff.b)];
        if (!valid(one) || !valid(two)) {
            continue;
        }
        RorWheel &w1a = wheels[static_cast<size_t>(one.a)];
        RorWheel &w1b = wheels[static_cast<size_t>(one.b)];
        RorWheel &w2a = wheels[static_cast<size_t>(two.a)];
        RorWheel &w2b = wheels[static_cast<size_t>(two.b)];
        const float in = w1a.torque + w1b.torque + w2a.torque + w2b.torque;
        float out_1 = 0.0f;
        float out_2 = 0.0f;
        diff.split((w1a.speed + w1b.speed) * 0.5f, (w2a.speed + w2b.speed) * 0.5f, in, dt, out_1, out_2);
        w1a.torque = w1b.torque = out_1 * 0.5f;
        w2a.torque = w2b.torque = out_2 * 0.5f;
    }
    for (RorDifferential &diff : m_wheel_diffs) {
        if (!valid(diff)) {
            continue;
        }
        RorWheel &a = wheels[static_cast<size_t>(diff.a)];
        RorWheel &b = wheels[static_cast<size_t>(diff.b)];
        diff.split(a.speed, b.speed, a.torque + b.torque, dt, a.torque, b.torque);
    }
}

void RorDifferentials::toggle_wheel_diffs() {
    for (RorDifferential &diff : m_wheel_diffs) {
        diff.toggle();
    }
}

void RorDifferentials::toggle_axle_diffs() {
    for (RorDifferential &diff : m_axle_diffs) {
        diff.toggle();
    }
}

char RorDifferentials::wheel_diff_type(int index) const {
    if (index < 0 || index >= wheel_diff_count() || m_wheel_diffs[static_cast<size_t>(index)].types.empty()) {
        return 0;
    }
    return static_cast<char>(m_wheel_diffs[static_cast<size_t>(index)].types[0]);
}

char RorDifferentials::axle_diff_type(int index) const {
    if (index < 0 || index >= axle_diff_count() || m_axle_diffs[static_cast<size_t>(index)].types.empty()) {
        return 0;
    }
    return static_cast<char>(m_axle_diffs[static_cast<size_t>(index)].types[0]);
}

} // namespace rorgd
