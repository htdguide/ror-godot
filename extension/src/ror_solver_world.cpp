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
    return m_heightfield.surface_at(m_frame.to_local(position));
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
    const bool hit = m_obstacles.contact(m_frame.to_local(position), penetration, normal, surface);
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
    return m_heightfield.height_at(m_frame.to_local(position));
}

Vector3 RorSolver::ground_normal_at(const Vector3 &position) const {
    sync();
    if (!m_heightfield.enabled()) {
        return Vector3(0.0f, 1.0f, 0.0f);
    }
    return m_heightfield.normal_at(m_frame.to_local(position));
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

// Moves the frame to the whole step nearest the rig once the rig's first node is more than a step
// from it, and tells the static world where it now is. Once per call to `step`, not per substep:
// a rig moves centimetres in a call. The shift is a whole number of steps and the coordinates it
// is taken from are under two steps, so every node lands on the same point it was at, exactly.
void RorSolver::follow_frame() {
    if (m_nodes.empty() || !m_frame_follows) {
        return;
    }
    const Vector3 lead = m_nodes.front().position;
    const double shift_x = std::abs(lead.x) > RorFrame::STEP_M ? RorFrame::snap(lead.x) : 0.0;
    const double shift_z = std::abs(lead.z) > RorFrame::STEP_M ? RorFrame::snap(lead.z) : 0.0;
    if (shift_x == 0.0 && shift_z == 0.0) {
        return;
    }
    shift_frame(shift_x, shift_z);
    ++m_frame_moves;
}

void RorSolver::add_collision_cab(int node_o, int node_a, int node_b) {
    sync();
    const int count = static_cast<int>(m_nodes.size());
    if (node_o < 0 || node_a < 0 || node_b < 0 || node_o >= count || node_a >= count ||
        node_b >= count) {
        return;
    }
    m_collcabs.add(node_o, node_a, node_b);
}

int RorSolver::collision_cab_count() const {
    sync();
    return static_cast<int>(m_collcabs.count());
}

void RorSolver::set_node_contact_role(int node, bool contacter, bool rim) {
    sync();
    m_collcabs.set_roles(node, m_nodes.size(), contacter, rim);
}

void RorSolver::add_command(int beam, int contract_key, int extend_key, float shorten_rate,
                            float lengthen_rate, float max_contraction, float max_extension,
                            bool force_restricted, bool auto_center, bool one_press,
                            bool one_press_center, float engine_coupling, bool needs_engine) {
    sync();
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return;
    }
    m_commands.add(beam, contract_key, extend_key, shorten_rate, lengthen_rate, max_contraction,
                   max_extension, force_restricted, auto_center, one_press, one_press_center,
                   engine_coupling, needs_engine);
}

int RorSolver::command_count() const {
    sync();
    return m_commands.count();
}

void RorSolver::set_command_key(int key, float value) {
    sync();
    m_commands.set_key(key, value);
}

void RorSolver::add_inertia_model(const String &name, const PackedFloat32Array &x, const PackedFloat32Array &y) {
    sync();
    std::vector<float> xs(x.ptr(), x.ptr() + x.size());
    std::vector<float> ys(y.ptr(), y.ptr() + y.size());
    m_commands.add_inertia_model(name.utf8().get_data(), xs, ys);
}

void RorSolver::set_command_inertia(int key, float start_delay, float stop_delay, const String &start,
                                    const String &stop) {
    sync();
    m_commands.set_key_inertia(key, start_delay, stop_delay, start.utf8().get_data(), stop.utf8().get_data());
}

bool RorSolver::command_key_has_inertia(int key) const {
    sync();
    return m_commands.key_has_inertia(key);
}

void RorSolver::set_node_tyre(int node) {
    sync();
    m_collcabs.set_tyre(node, m_nodes.size());
}

void RorSolver::set_self_collision(bool enabled) {
    sync();
    m_self_collision = enabled;
}

int64_t RorSolver::self_contact_count() const {
    sync();
    return m_self_contacts;
}

void RorSolver::set_node_ground_contact(int node, bool touches) {
    sync();
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[static_cast<size_t>(node)].no_ground_contact = !touches;
        m_collcabs.prepared_nodes = 0;
    }
}

int RorSolver::contactable_count() {
    sync();
    m_collcabs.prepare(m_nodes, m_beams);
    return static_cast<int>(m_collcabs.contactable_count());
}

void RorSolver::set_collision_range(float metres) {
    sync();
    m_collcabs.range = metres;
}

Vector2i RorSolver::get_beam_nodes(int beam) const {
    sync();
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return Vector2i(-1, -1);
    }
    return Vector2i(m_beams[static_cast<size_t>(beam)].a, m_beams[static_cast<size_t>(beam)].b);
}

float RorSolver::get_beam_damping(int beam) const {
    sync();
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return 0.0f;
    }
    return m_beams[static_cast<size_t>(beam)].damping;
}

void RorSolver::set_beam_damping(int beam, float damping) {
    sync();
    if (beam >= 0 && beam < static_cast<int>(m_beams.size())) {
        m_beams[static_cast<size_t>(beam)].damping = damping;
    }
}

// Moves the frame by a whole number of steps, every node by the opposite, and tells the static
// world where the frame now is.
void RorSolver::shift_frame(double shift_x, double shift_z) {
    for (RorNode &node : m_nodes) {
        node.position.x = static_cast<float>(static_cast<double>(node.position.x) - shift_x);
        node.position.z = static_cast<float>(static_cast<double>(node.position.z) - shift_z);
    }
    m_frame.x += shift_x;
    m_frame.z += shift_z;
    m_heightfield.set_frame(m_frame);
    m_obstacles.set_frame(m_frame);
    m_triangles.set_frame(m_frame);
}

void RorSolver::set_frame_origin(double x, double z) {
    sync();
    if (!m_frame_follows) {
        return;
    }
    const double shift_x = RorFrame::snap(x) - m_frame.x;
    const double shift_z = RorFrame::snap(z) - m_frame.z;
    shift_frame(shift_x, shift_z);
}

double RorSolver::frame_origin_x() const {
    sync();
    return m_frame.x;
}

double RorSolver::frame_origin_z() const {
    sync();
    return m_frame.z;
}

void RorSolver::set_node_local_position(int node, const Vector3 &local) {
    sync();
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[static_cast<size_t>(node)].position = local;
    }
}

void RorSolver::set_frame_follows(bool follows) {
    sync();
    m_frame_follows = follows;
}

int64_t RorSolver::frame_moves() const {
    sync();
    return m_frame_moves;
}

} // namespace rorgd
