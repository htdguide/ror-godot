#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// The node/beam core of Rigs of Rods' soft-body simulation.
//
// Point masses joined by damped springs, integrated with symplectic (semi-implicit)
// Euler exactly as upstream does it: velocity from the force accumulated during the
// previous step, then position from the new velocity, then the accumulator reset to
// gravity for every other force to add onto.
//
// This is the core only. Wheels, shocks, hydros, aerodynamics, buoyancy and collision are
// separate force sources upstream and are not here yet; the order in which they run is
// part of Rigs of Rods' behaviour, so they are added deliberately rather than
// opportunistically.
class RorSolver : public godot::RefCounted {
    GDCLASS(RorSolver, godot::RefCounted)

protected:
    static void _bind_methods();

public:
    // Returns the new node's index.
    int add_node(const godot::Vector3 &position, float mass);
    // Returns the new beam's index. A rest length of 0 or less takes the current
    // separation of the two nodes, which is how a rig at spawn defines itself.
    int add_beam(int node_a, int node_b, float rest_length, float spring, float damping);

    void set_gravity(const godot::Vector3 &gravity);
    // A flat hard ground at `height`. Upstream's contact law, not a penalty spring: see
    // the implementation for why that distinction decides whether a rig is stable.
    void set_ground(float height, bool enabled);
    void set_node_immovable(int node, bool immovable);
    void set_node_position(int node, const godot::Vector3 &position);
    void set_node_velocity(int node, const godot::Vector3 &velocity);

    // Advances by `substeps` steps of `dt` seconds each.
    void step(float dt, int substeps);

    godot::PackedVector3Array get_positions() const;
    godot::Vector3 get_node_position(int node) const;
    godot::Vector3 get_node_velocity(int node) const;
    int node_count() const;
    int beam_count() const;
    // Total kinetic plus gravitational potential energy, for checking that a rig settles
    // rather than gaining energy from its own integrator.
    float total_energy() const;

private:
    struct Node {
        godot::Vector3 position;
        godot::Vector3 velocity;
        godot::Vector3 forces;
        float mass = 1.0f;
        bool immovable = false;
    };

    struct Beam {
        int a = 0;
        int b = 0;
        float rest_length = 0.0f;
        float spring = 0.0f;
        float damping = 0.0f;
    };

    std::vector<Node> m_nodes;
    std::vector<Beam> m_beams;
    godot::Vector3 m_gravity = godot::Vector3(0.0f, -9.81f, 0.0f);
    float m_ground_height = 0.0f;
    bool m_ground_enabled = false;

    void integrate(float dt);
    void accumulate_beam_forces();
    void apply_ground_contact(float dt);
};

} // namespace rorgd
