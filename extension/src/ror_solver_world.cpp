#include "ror_solver.h"

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>

// The world a rig stands in: the ground models, the heightfield and its surface map, and the
// obstacles. Split out of ror_solver.cpp when the threading guards took that file to its cap; it
// is a real seam too, since nothing here moves during a step and everything here is set up
// before the first one.

using namespace godot;

namespace rorgd {

void RorSolver::set_ground_friction(float adhesion_velocity, float static_friction, float sliding_friction,
                                    float hydrodynamic_friction, float stribeck_velocity, float strength) {
    sync();
    set_ground_model(0, adhesion_velocity, static_friction, sliding_friction, hydrodynamic_friction,
                     stribeck_velocity, m_ground_models[0].alpha, strength);
}

bool RorSolver::set_surface_map(const PackedByteArray &surfaces, int width, int depth) {
    sync();
    return m_heightfield.set_surfaces(surfaces, width, depth);
}

int RorSolver::ground_model_count() const {
    sync();
    return static_cast<int>(m_ground_models.size());
}
int RorSolver::surface_at(const Vector3 &position) const {
    sync();
    return m_heightfield.surface_at(position);
}

void RorSolver::set_ground_fluid(int index, float solid_ground_level, float fluid_density,
                                 float flow_consistency_index, float flow_behavior_index,
                                 float drag_anisotropy) {
    sync();
    ground_model_at(m_ground_models, index, [&](RorGroundModel &model) {
        model.solid_ground_level = solid_ground_level;
        model.fluid_density = fluid_density;
        model.flow_consistency_index = flow_consistency_index;
        model.flow_behavior_index = flow_behavior_index;
        model.drag_anisotropy = drag_anisotropy;
    });
}

void RorSolver::set_ground_model(int index, float adhesion_velocity, float static_friction,
                                 float sliding_friction, float hydrodynamic_friction,
                                 float stribeck_velocity, float alpha, float strength) {
    sync();
    ground_model_at(m_ground_models, index, [&](RorGroundModel &model) {
        model.adhesion_velocity = adhesion_velocity;
        model.static_friction = static_friction;
        model.sliding_friction = sliding_friction;
        model.hydrodynamic_friction = hydrodynamic_friction;
        model.stribeck_velocity = stribeck_velocity;
        model.alpha = alpha;
        model.strength = strength;
    });
}

bool RorSolver::set_heightfield(const PackedFloat32Array &heights, int width, int depth,
                                const Vector3 &origin, float spacing) {
    sync();
    return m_heightfield.set_field(heights, width, depth, origin, spacing);
}

int RorSolver::add_obstacle_box(const Transform3D &transform, const Vector3 &half_extents,
                                int surface) {
    sync();
    return m_obstacles.add_box(transform, half_extents, surface);
}

void RorSolver::clear_obstacles() {
    sync();
    m_obstacles.clear();
}

Dictionary RorSolver::obstacle_contact(const Vector3 &position) {
    sync();
    Dictionary out;
    const Vector3 margin(0.001f, 0.001f, 0.001f);
    m_obstacles.select(position - margin, position + margin);
    float penetration = 0.0f;
    Vector3 normal;
    int surface = 0;
    const bool hit = m_obstacles.contact(position, penetration, normal, surface);
    out["hit"] = hit;
    out["penetration"] = penetration;
    out["normal"] = normal;
    out["surface"] = surface;
    return out;
}

int RorSolver::obstacle_count() const {
    sync();
    return static_cast<int>(m_obstacles.count());
}

void RorSolver::clear_heightfield() {
    sync();
    m_heightfield.clear();
}

float RorSolver::ground_height_at(const Vector3 &position) const {
    sync();
    if (!m_heightfield.enabled()) {
        return m_ground_height;
    }
    return m_heightfield.height_at(position);
}

Vector3 RorSolver::ground_normal_at(const Vector3 &position) const {
    sync();
    if (!m_heightfield.enabled()) {
        return Vector3(0.0f, 1.0f, 0.0f);
    }
    return m_heightfield.normal_at(position);
}

Vector3 RorSolver::ground_contact_probe(const Vector3 &velocity, const Vector3 &forces, float mass,
                                        float friction_coef, const Vector3 &normal,
                                        float penetration, float dt) const {
    sync();
    RorNode node;
    node.velocity = velocity;
    node.forces = forces;
    node.mass = mass;
    node.friction_coef = friction_coef;
    // Model 0: the parity comparison is against upstream's default surface.
    return ground_contact_force(node, normal, penetration, dt, m_ground_models[0]);
}

} // namespace rorgd
