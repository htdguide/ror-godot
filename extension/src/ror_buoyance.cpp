#include "ror_buoyance.h"

#include <cmath>

using godot::Vector3;

namespace rorgd {

namespace {
// Upstream's sampling: every 10 substeps (200 a second), and its `PHYSICS_DT`.
constexpr int BUOYANCY_SAMPLING_INTERVAL = 10;
constexpr float PHYSICS_DT = 0.0005f;

inline float compute_volume(Vector3 o, Vector3 a, Vector3 b, Vector3 c) {
    return ((a - o).dot((b - o).cross(c - o))) / 6.0;
}
} // namespace

int RorBuoyance::cache(int node) {
    for (size_t i = 0; i < m_cached.size(); ++i) {
        if (m_cached[i].nodenum == node) {
            return static_cast<int>(i);
        }
    }
    CachedNode cached;
    cached.nodenum = node;
    m_cached.push_back(cached);
    m_projected.push_back(cached);
    return static_cast<int>(m_cached.size()) - 1;
}

void RorBuoyance::add_cab(int a, int b, int c, int type) {
    Cab cab;
    cab.ids[0] = cache(a);
    cab.ids[1] = cache(b);
    cab.ids[2] = cache(c);
    cab.type = type;
    m_cabs.push_back(cab);
}

Vector3 RorBuoyance::pressure_force_sub(Vector3 a, Vector3 b, Vector3 c, Vector3 vel, int type) const {
    Vector3 normal = (b - a).cross(c - a);
    float surf = normal.length();
    if (surf < 0.00001) {
        return Vector3();
    }
    normal = normal / surf;
    surf = surf / 2.0;
    float vol = 0.0;
    if (type != BUOY_DRAGONLY) {
        const Vector3 ap = a + (m_height - a.y) * 9810 * normal;
        const Vector3 bp = b + (m_height - b.y) * 9810 * normal;
        const Vector3 cp = c + (m_height - c.y) * 9810 * normal;
        const Vector3 ctd = (a + b + c + ap + bp + cp) / 6.0;
        vol += compute_volume(ctd, a, b, c);
        vol += compute_volume(ctd, a, ap, bp);
        vol += compute_volume(ctd, a, bp, b);
        vol += compute_volume(ctd, b, bp, cp);
        vol += compute_volume(ctd, b, cp, c);
        vol += compute_volume(ctd, c, cp, ap);
        vol += compute_volume(ctd, c, ap, a);
        vol += compute_volume(ctd, ap, cp, bp);
    }
    Vector3 drg;
    if (type != BUOY_DRAGLESS) {
        // Still water: upstream subtracts the waves' velocity, zero with waves off.
        const float vell = vel.length();
        if (vell > 0.01) {
            const float cosaoa = std::fabs(normal.dot(vel / vell));
            drg = (-500.0 * surf * vell * vell * cosaoa) * normal;
            if (normal.dot(vel / vell) < 0) {
                drg = -drg;
            }
        }
    }
    if (sink) {
        return drg;
    }
    return vol * normal + drg;
}

Vector3 RorBuoyance::pressure_force(Vector3 a, Vector3 b, Vector3 c, Vector3 vel, int type) const {
    const float wha = m_height;
    if (a.y > wha && b.y > wha && c.y > wha) {
        return Vector3();
    }
    if (a.y > wha || b.y > wha || c.y > wha) {
        if (a.y < wha && b.y > wha && c.y > wha) {
            return pressure_force_sub(a, a + (wha - a.y) / (b.y - a.y) * (b - a), a + (wha - a.y) / (c.y - a.y) * (c - a), vel, type);
        }
        if (b.y < wha && c.y > wha && a.y > wha) {
            return pressure_force_sub(b, b + (wha - b.y) / (c.y - b.y) * (c - b), b + (wha - b.y) / (a.y - b.y) * (a - b), vel, type);
        }
        if (c.y < wha && a.y > wha && b.y > wha) {
            return pressure_force_sub(c, c + (wha - c.y) / (a.y - c.y) * (a - c), c + (wha - c.y) / (b.y - c.y) * (b - c), vel, type);
        }
        if (a.y > wha && b.y < wha && c.y < wha) {
            const Vector3 tb = a + (wha - a.y) / (b.y - a.y) * (b - a);
            const Vector3 tc = a + (wha - a.y) / (c.y - a.y) * (c - a);
            const Vector3 f = pressure_force_sub(tb, b, tc, vel, type);
            return f + pressure_force_sub(tc, b, c, vel, type);
        }
        if (b.y > wha && c.y < wha && a.y < wha) {
            const Vector3 tc = b + (wha - b.y) / (c.y - b.y) * (c - b);
            const Vector3 ta = b + (wha - b.y) / (a.y - b.y) * (a - b);
            const Vector3 f = pressure_force_sub(tc, c, ta, vel, type);
            return f + pressure_force_sub(ta, c, a, vel, type);
        }
        if (c.y > wha && a.y < wha && b.y < wha) {
            const Vector3 ta = c + (wha - c.y) / (a.y - c.y) * (a - c);
            const Vector3 tb = c + (wha - c.y) / (b.y - c.y) * (b - c);
            const Vector3 f = pressure_force_sub(ta, a, tb, vel, type);
            return f + pressure_force_sub(tb, a, b, vel, type);
        }
        return Vector3();
    }
    return pressure_force_sub(a, b, c, vel, type);
}

void RorBuoyance::compute_node_force(CachedNode &a, CachedNode &b, CachedNode &c, int type) const {
    if (a.pos.y > m_height && b.pos.y > m_height && c.pos.y > m_height) {
        return;
    }
    const Vector3 m = (a.pos + b.pos + c.pos) / 3.0;
    const Vector3 mab = (a.pos + b.pos) / 2.0;
    const Vector3 mbc = (b.pos + c.pos) / 2.0;
    const Vector3 mca = (c.pos + a.pos) / 2.0;
    const Vector3 vel = (a.vel + b.vel + c.vel) / 3.0;
    a.forces += pressure_force(a.pos, mab, m, vel, type) + pressure_force(a.pos, m, mca, vel, type);
    b.forces += pressure_force(b.pos, mbc, m, vel, type) + pressure_force(b.pos, m, mab, vel, type);
    c.forces += pressure_force(c.pos, mca, m, vel, type) + pressure_force(c.pos, m, mbc, vel, type);
}

void RorBuoyance::update(NodeArray &nodes, float /*dt*/) {
    if (!m_has_water || m_cabs.empty()) {
        return;
    }
    if (m_total_steps % BUOYANCY_SAMPLING_INTERVAL == 0) {
        const float timeshift_sec = PHYSICS_DT * BUOYANCY_SAMPLING_INTERVAL;
        for (size_t i = 0; i < m_cached.size(); ++i) {
            const RorNode &node = nodes[static_cast<size_t>(m_cached[i].nodenum)];
            m_cached[i].pos = node.position;
            m_cached[i].vel = node.velocity;
            m_cached[i].forces = Vector3();
            m_projected[i].pos = node.position + node.velocity * timeshift_sec;
            m_projected[i].vel = node.velocity;
            m_projected[i].forces = Vector3();
        }
        for (const Cab &cab : m_cabs) {
            compute_node_force(m_cached[static_cast<size_t>(cab.ids[0])], m_cached[static_cast<size_t>(cab.ids[1])],
                               m_cached[static_cast<size_t>(cab.ids[2])], cab.type);
            compute_node_force(m_projected[static_cast<size_t>(cab.ids[0])], m_projected[static_cast<size_t>(cab.ids[1])],
                               m_projected[static_cast<size_t>(cab.ids[2])], cab.type);
        }
        for (const CachedNode &cached : m_cached) {
            nodes[static_cast<size_t>(cached.nodenum)].forces += cached.forces;
        }
        m_last_sample_steps = m_total_steps;
    } else {
        const float interp_ratio = static_cast<double>(m_total_steps - m_last_sample_steps) / BUOYANCY_SAMPLING_INTERVAL;
        for (size_t i = 0; i < m_cached.size(); ++i) {
            const Vector3 &force_a = m_cached[i].forces;
            const Vector3 &force_b = m_projected[i].forces;
            const Vector3 interp_force = force_a * (1.0f - interp_ratio) + force_b * interp_ratio;
            nodes[static_cast<size_t>(m_cached[i].nodenum)].forces += interp_force;
        }
    }
    m_total_steps++;
}

} // namespace rorgd
