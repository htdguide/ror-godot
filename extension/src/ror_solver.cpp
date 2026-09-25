#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace rorgd {

void RorSolver::_bind_methods() {
    ClassDB::bind_method(D_METHOD("add_node", "position", "mass"), &RorSolver::add_node);
    ClassDB::bind_method(D_METHOD("add_beam", "node_a", "node_b", "rest_length", "spring", "damping"),
                         &RorSolver::add_beam);
    ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &RorSolver::set_gravity);
    ClassDB::bind_method(D_METHOD("set_ground", "height", "enabled"), &RorSolver::set_ground);
    ClassDB::bind_method(D_METHOD("set_node_immovable", "node", "immovable"),
                         &RorSolver::set_node_immovable);
    ClassDB::bind_method(D_METHOD("set_node_position", "node", "position"),
                         &RorSolver::set_node_position);
    ClassDB::bind_method(D_METHOD("set_node_velocity", "node", "velocity"),
                         &RorSolver::set_node_velocity);
    ClassDB::bind_method(D_METHOD("step", "dt", "substeps"), &RorSolver::step);
    ClassDB::bind_method(D_METHOD("get_positions"), &RorSolver::get_positions);
    ClassDB::bind_method(D_METHOD("get_node_position", "node"), &RorSolver::get_node_position);
    ClassDB::bind_method(D_METHOD("get_node_velocity", "node"), &RorSolver::get_node_velocity);
    ClassDB::bind_method(D_METHOD("node_count"), &RorSolver::node_count);
    ClassDB::bind_method(D_METHOD("beam_count"), &RorSolver::beam_count);
    ClassDB::bind_method(D_METHOD("total_energy"), &RorSolver::total_energy);
}

int RorSolver::add_node(const Vector3 &position, float mass) {
    Node node;
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
    Beam beam;
    beam.a = node_a;
    beam.b = node_b;
    beam.rest_length = rest_length > 0.0f
            ? rest_length
            : static_cast<float>((m_nodes[node_a].position - m_nodes[node_b].position).length());
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

void RorSolver::step(float dt, int substeps) {
    for (int i = 0; i < substeps; ++i) {
        integrate(dt);
        accumulate_beam_forces();
        // Last, because the contact law works on the node's fully accumulated force.
        apply_ground_contact(dt);
    }
}

// Velocity from the force accumulated last step, then position from the new velocity,
// then reset the accumulator to gravity. Upstream's order, which is what makes the
// integrator symplectic and keeps a rig from gaining energy at rest.
void RorSolver::integrate(float dt) {
    for (Node &node : m_nodes) {
        if (!node.immovable) {
            node.velocity += node.forces / node.mass * dt;
            node.position += node.velocity * dt;
        }
        node.forces = m_gravity * node.mass;
    }
}

void RorSolver::accumulate_beam_forces() {
    for (const Beam &beam : m_beams) {
        Node &a = m_nodes[beam.a];
        Node &b = m_nodes[beam.b];
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

// Upstream's contact law, and the reason it is not a penalty spring: a spring stiff
// enough to hold a vehicle up would need a timestep far below 0.5 ms to stay stable. This
// instead removes the force pushing a node into the ground and adds exactly the impulse
// needed to stop its approach within one step, which is what lets an explicit integrator
// sit on hard ground at 2 kHz.
//
// Friction and the fluid ground models are not here yet; this is a hard, frictionless
// plane.
void RorSolver::apply_ground_contact(float dt) {
    if (!m_ground_enabled || dt <= 0.0f) {
        return;
    }
    const Vector3 normal(0.0f, 1.0f, 0.0f);
    for (Node &node : m_nodes) {
        if (node.immovable) {
            continue;
        }
        const float penetration = m_ground_height - static_cast<float>(node.position.y);
        if (penetration < 0.0f) {
            continue;
        }
        // Remove whatever is still pushing the node further into the ground.
        const float normal_force = static_cast<float>(node.forces.dot(normal));
        if (normal_force < 0.0f) {
            node.forces -= normal * normal_force;
        }
        // Stop the approach within a step, and correct the depth already accumulated.
        const float approach = static_cast<float>(node.velocity.dot(normal));
        if (approach < 0.0f) {
            node.forces -= normal * (0.8f * approach - 0.2f * penetration / dt) * node.mass / dt;
        }
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

int RorSolver::node_count() const {
    return static_cast<int>(m_nodes.size());
}

int RorSolver::beam_count() const {
    return static_cast<int>(m_beams.size());
}

float RorSolver::total_energy() const {
    float energy = 0.0f;
    for (const Node &node : m_nodes) {
        if (node.immovable) {
            continue;
        }
        const float speed = static_cast<float>(node.velocity.length());
        energy += 0.5f * node.mass * speed * speed;
        energy += -node.mass * static_cast<float>(m_gravity.dot(node.position));
    }
    for (const Beam &beam : m_beams) {
        const float length =
                static_cast<float>((m_nodes[beam.a].position - m_nodes[beam.b].position).length());
        const float extension = length - beam.rest_length;
        energy += 0.5f * beam.spring * extension * extension;
    }
    return energy;
}

} // namespace rorgd
