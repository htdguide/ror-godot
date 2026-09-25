#include "ror_solver.h"

#include <cmath>

using namespace godot;

namespace rorgd {

namespace {
// Radians per second to RPM. Upstream's RAD_PER_SEC_TO_RPM, and the unit its drivetrain
// expects the driveshaft speed in.
constexpr float RAD_PER_SEC_TO_RPM = 9.5492965855137f;
} // namespace

int RorSolver::add_node(const Vector3 &position, float mass) {
    RorNode node;
    node.position = position;
    node.mass = mass > 0.0f ? mass : 1.0f;
    m_nodes.push_back(node);
    return static_cast<int>(m_nodes.size()) - 1;
}

int RorSolver::add_beam(int node_a, int node_b, float rest_length, float spring, float damping) {
    if (node_a < 0 || node_b < 0 || node_a >= static_cast<int>(m_nodes.size()) ||
        node_b >= static_cast<int>(m_nodes.size())) {
        return -1;
    }
    RorBeam beam;
    beam.a = node_a;
    beam.b = node_b;
    beam.rest_length = rest_length > 0.0f
            ? rest_length
            : static_cast<float>((m_nodes[node_a].position - m_nodes[node_b].position).length());
    beam.reference_length = beam.rest_length;
    beam.spring = spring;
    beam.damping = damping;
    m_beams.push_back(beam);
    return static_cast<int>(m_beams.size()) - 1;
}

void RorSolver::set_gravity(const Vector3 &gravity) {
    m_gravity = gravity;
}

void RorSolver::set_ground(float height, bool enabled) {
    m_ground_height = height;
    m_ground_enabled = enabled;
}

void RorSolver::set_ground_friction(float adhesion_velocity, float static_friction, float sliding_friction,
                                    float hydrodynamic_friction, float stribeck_velocity, float strength) {
    m_ground_model.adhesion_velocity = adhesion_velocity;
    m_ground_model.static_friction = static_friction;
    m_ground_model.sliding_friction = sliding_friction;
    m_ground_model.hydrodynamic_friction = hydrodynamic_friction;
    m_ground_model.stribeck_velocity = stribeck_velocity;
    m_ground_model.strength = strength;
}

void RorSolver::set_air_drag(float coefficient, bool enabled) {
    m_air_drag = coefficient;
    m_air_drag_enabled = enabled;
}

void RorSolver::set_node_immovable(int node, bool immovable) {
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[node].immovable = immovable;
    }
}

void RorSolver::set_node_position(int node, const Vector3 &position) {
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[node].position = position;
    }
}

void RorSolver::set_node_velocity(int node, const Vector3 &velocity) {
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[node].velocity = velocity;
    }
}

void RorSolver::set_node_mass(int node, float mass) {
    if (node >= 0 && node < static_cast<int>(m_nodes.size()) && mass > 0.0f) {
        m_nodes[node].mass = mass;
    }
}

void RorSolver::set_node_friction(int node, float friction_coef) {
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[node].friction_coef = friction_coef;
    }
}

void RorSolver::add_node_force(int node, const Vector3 &force) {
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[node].forces += force;
    }
}

void RorSolver::set_beam_rest_length(int beam, float length) {
    if (beam >= 0 && beam < static_cast<int>(m_beams.size())) {
        m_beams[beam].rest_length = length;
    }
}

float RorSolver::get_beam_rest_length(int beam) const {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return 0.0f;
    }
    return m_beams[beam].rest_length;
}

float RorSolver::get_beam_reference_length(int beam) const {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return 0.0f;
    }
    return m_beams[beam].reference_length;
}

// Upstream's order, and each step is one whole pass of it. The drivetrain runs at the
// same rate as the rest: its clutch couples an engine of 0.12 kg m2 to the road through a
// stiff spring, and at frame rate that system does not integrate.
void RorSolver::step(float dt, int substeps) {
    for (int i = 0; i < substeps; ++i) {
        integrate(dt);
        apply_air_drag();
        m_steering.update(dt, m_wheels.driven_speed(), m_beams);
        // The first substep of a call stands in for upstream's per-frame pass, which is
        // the rate it makes gear decisions at.
        m_drivetrain.step(dt, m_wheels.driven_spin() * RAD_PER_SEC_TO_RPM, i == 0);
        m_wheels.apply(m_nodes, m_drivetrain.clutch_torque(), dt);
        accumulate_beam_forces();
        // Last, because the contact law works on the node's fully accumulated force.
        apply_ground_contact(dt);
    }
}

// Velocity from the force accumulated last step, then position from the new velocity,
// then reset the accumulator to gravity. Upstream's order, which is what makes the
// integrator symplectic and keeps a rig from gaining energy at rest.
void RorSolver::integrate(float dt) {
    for (RorNode &node : m_nodes) {
        if (!node.immovable) {
            node.velocity += node.forces / node.mass * dt;
            node.position += node.velocity * dt;
        }
        node.forces = m_gravity * node.mass;
        node.ground_contact = false;
    }
}

// Viscous drag, quadratic in speed. Small at walking pace and the dominant damping at
// road speed, which is why a rig without it keeps vibrating long after it should have
// settled and needs a smaller timestep to stay stable.
void RorSolver::apply_air_drag() {
    if (!m_air_drag_enabled) {
        return;
    }
    for (RorNode &node : m_nodes) {
        const float speed = static_cast<float>(node.velocity.length());
        if (speed <= 0.0f) {
            continue;
        }
        node.forces -= node.velocity * (m_air_drag * speed);
    }
}

void RorSolver::accumulate_beam_forces() {
    for (const RorBeam &beam : m_beams) {
        RorNode &a = m_nodes[beam.a];
        RorNode &b = m_nodes[beam.b];
        const Vector3 separation = a.position - b.position;
        const float length = static_cast<float>(separation.length());
        if (length <= 0.0f) {
            continue;
        }
        const Vector3 direction = separation / length;
        // Positive when stretched, negative when compressed.
        const float extension = length - beam.rest_length;
        // Rate of stretch along the beam, which is what the damper resists.
        const float closing_speed = (a.velocity - b.velocity).dot(direction);
        const float magnitude = -beam.spring * extension - beam.damping * closing_speed;
        const Vector3 force = direction * magnitude;
        a.forces += force;
        b.forces -= force;
    }
}

void RorSolver::apply_ground_contact(float dt) {
    if (!m_ground_enabled || dt <= 0.0f) {
        return;
    }
    const Vector3 normal(0.0f, 1.0f, 0.0f);
    for (RorNode &node : m_nodes) {
        if (node.immovable) {
            continue;
        }
        const float penetration = m_ground_height - static_cast<float>(node.position.y);
        if (penetration < 0.0f) {
            continue;
        }
        node.ground_contact = true;
        node.forces += ground_contact_force(node, normal, penetration, dt, m_ground_model);
    }
}

PackedVector3Array RorSolver::get_positions() const {
    PackedVector3Array out;
    out.resize(static_cast<int64_t>(m_nodes.size()));
    for (size_t i = 0; i < m_nodes.size(); ++i) {
        out[static_cast<int64_t>(i)] = m_nodes[i].position;
    }
    return out;
}

Vector3 RorSolver::get_node_position(int node) const {
    if (node < 0 || node >= static_cast<int>(m_nodes.size())) {
        return Vector3();
    }
    return m_nodes[node].position;
}

Vector3 RorSolver::get_node_velocity(int node) const {
    if (node < 0 || node >= static_cast<int>(m_nodes.size())) {
        return Vector3();
    }
    return m_nodes[node].velocity;
}

float RorSolver::get_node_mass(int node) const {
    if (node < 0 || node >= static_cast<int>(m_nodes.size())) {
        return 0.0f;
    }
    return m_nodes[node].mass;
}

int RorSolver::node_count() const {
    return static_cast<int>(m_nodes.size());
}

int RorSolver::beam_count() const {
    return static_cast<int>(m_beams.size());
}

float RorSolver::total_mass() const {
    float mass = 0.0f;
    for (const RorNode &node : m_nodes) {
        mass += node.mass;
    }
    return mass;
}

float RorSolver::total_energy() const {
    float energy = 0.0f;
    for (const RorNode &node : m_nodes) {
        if (node.immovable) {
            continue;
        }
        const float speed = static_cast<float>(node.velocity.length());
        energy += 0.5f * node.mass * speed * speed;
        energy += -node.mass * static_cast<float>(m_gravity.dot(node.position));
    }
    for (const RorBeam &beam : m_beams) {
        const float length =
                static_cast<float>((m_nodes[beam.a].position - m_nodes[beam.b].position).length());
        const float extension = length - beam.rest_length;
        energy += 0.5f * beam.spring * extension * extension;
    }
    return energy;
}

} // namespace rorgd
