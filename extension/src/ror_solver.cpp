#include "ror_solver.h"

#include "ror_deform.h"
#include "ror_drag.h"

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include "ror_approx.h"

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
    // Upstream's break rule counts how many unbroken beams still hold a node, so the count is
    // kept as beams are added rather than searched for when one is about to break.
    m_nodes[static_cast<size_t>(node_a)].active_beams += 1;
    m_nodes[static_cast<size_t>(node_b)].active_beams += 1;
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
    set_ground_model(0, adhesion_velocity, static_friction, sliding_friction, hydrodynamic_friction,
                     stribeck_velocity, m_ground_models[0].alpha, strength);
}

bool RorSolver::set_surface_map(const PackedByteArray &surfaces, int width, int depth) {
    return m_heightfield.set_surfaces(surfaces, width, depth);
}
int RorSolver::ground_model_count() const { return static_cast<int>(m_ground_models.size()); }
int RorSolver::surface_at(const Vector3 &position) const {
    return m_heightfield.surface_at(position);
}

void RorSolver::set_fuselage_drag(int front_node, float width, bool enabled) {
    m_fuselage_node = front_node;
    m_fuselage_width = width;
    m_fuselage_enabled = enabled && front_node >= 0 && width > 0.0f;
}

void RorSolver::set_ground_fluid(int index, float solid_ground_level, float fluid_density,
                                 float flow_consistency_index, float flow_behavior_index,
                                 float drag_anisotropy) {
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

void RorSolver::set_beam_bounds(int beam, int bound_type, float short_bound, float long_bound,
                                float bound_spring, float bound_damp, float precompression) {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return;
    }
    RorBeam &target = m_beams[beam];
    target.bound = static_cast<BeamBound>(bound_type);
    target.short_bound = short_bound;
    target.long_bound = long_bound;
    target.bound_spring = bound_spring;
    target.bound_damp = bound_damp;
    if (precompression > 0.0f && precompression != 1.0f) {
        target.rest_length *= precompression;
        target.reference_length *= precompression;
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

float RorSolver::get_beam_length(int beam) const {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return 0.0f;
    }
    const Vector3 separation =
            m_nodes[m_beams[beam].a].position - m_nodes[m_beams[beam].b].position;
    const float squared = static_cast<float>(separation.length_squared());
    if (squared <= 0.0f) {
        return 0.0f;
    }
    return squared * fast_invSqrt(squared);
}

// Upstream's order, and each step is one whole pass of it. The drivetrain runs at the
// same rate as the rest: its clutch couples an engine of 0.12 kg m2 to the road through a
// stiff spring, and at frame rate that system does not integrate.
void RorSolver::step(float dt, int substeps) {
    // The obstacles near the rig, found once per call rather than per substep: they never move,
    // the rig moves centimetres inside one call, and testing every box against every node at
    // 2 kHz would cost more than the simulation it is protecting.
    select_nearby_obstacles();
    for (int i = 0; i < substeps; ++i) {
        integrate(dt);
        apply_air_drag();
        m_steering.update(dt, m_wheels.driven_speed(), m_beams);
        // The first substep of a call stands in for upstream's per-frame pass, which is
        // the rate it makes gear decisions at.
        m_drivetrain.step(dt, m_wheels.driven_spin() * RAD_PER_SEC_TO_RPM, i == 0);
        m_wheels.apply(m_nodes, m_drivetrain.clutch_torque(), dt);
        accumulate_beam_forces();
        // Before the ground, because a slide node is structure: it is what holds a strut's hub
        // on its travel, and the contact law below wants a node's structural force already in.
        apply_slide_nodes(m_slide_nodes, m_nodes);
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

// Which of the two aerodynamic models this rig gets, which is upstream's own branch: a rig that
// declares a fuselage is dragged as one body, and everything else node by node. The difference
// is not small — the hero truck declares a 0.1 m fuselage, and given the turbulent model instead
// it tops out at 63 km/h in fourth gear with the throttle on the floor. Both laws are in
// ror_drag.
void RorSolver::apply_air_drag() {
    if (m_fuselage_enabled) {
        apply_fuselage_drag(m_nodes, m_fuselage_node, m_fuselage_width);
        return;
    }
    if (!m_air_drag_enabled) {
        return;
    }
    apply_turbulent_drag(m_nodes, m_air_drag);
}

void RorSolver::accumulate_beam_forces() {
    for (RorBeam &beam : m_beams) {
        if (beam.broken) {
            continue;
        }
        RorNode &a = m_nodes[beam.a];
        RorNode &b = m_nodes[beam.b];
        const Vector3 separation = a.position - b.position;
        const float squared = static_cast<float>(separation.length_squared());
        if (squared <= 0.0f) {
            continue;
        }
        // Upstream divides every beam length by the Quake reciprocal square root, accurate to
        // about 0.2%, and never computes an exact length at all. Every force in a Rigs of Rods
        // rig carries that, so computing it exactly here would be a different simulation.
        const float inverted_length = fast_invSqrt(squared);
        const float length = squared * inverted_length;
        // Positive when stretched, negative when compressed. Upstream's `difftoBeamL`.
        const float extension = length - beam.rest_length;
        // Rate of stretch along the beam, which is what the damper resists.
        const float closing_speed =
                static_cast<float>((a.velocity - b.velocity).dot(separation)) * inverted_length;
        float spring = beam.spring;
        float damping = beam.damping;
        apply_bound_law(beam, extension, spring, damping);
        float stress = -spring * extension - damping * closing_speed;
        stress = apply_beam_deformation(beam, extension, spring, stress, m_nodes);
        if (beam.broken) {
            continue;
        }
        const Vector3 force = separation * (stress * inverted_length);
        a.forces += force;
        b.forces -= force;
    }
}

void RorSolver::set_beam_limits(int beam, float deform, float strength, float plastic_coef) {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return;
    }
    RorBeam &target = m_beams[static_cast<size_t>(beam)];
    target.max_pos_stress = deform;
    target.max_neg_stress = -deform;
    target.minmax_stress = deform;
    target.strength = strength;
    target.plastic_coef = plastic_coef;
    // Only ordinary structural beams deform; shocks, ropes and support beams have their own
    // laws and upstream exempts them.
    target.deformable = target.bound == BeamBound::NORMAL;
}

void RorSolver::add_slide_node(int node, const PackedInt32Array &rail, float spring,
                               float break_force, float tolerance) {
    if (node < 0 || node >= static_cast<int>(m_nodes.size()) || rail.size() < 2) { return; }
    RorSlideNode slide;
    slide.node = node;
    slide.rail.reserve(static_cast<size_t>(rail.size()));
    for (int i = 0; i < rail.size(); ++i) { slide.rail.push_back(rail[i]); }
    slide.spring = spring;
    // Upstream's "never breaks" is an infinite force; this carries it as zero.
    slide.break_force = std::isfinite(break_force) ? break_force : 0.0f;
    slide.tolerance = tolerance;
    m_slide_nodes.push_back(slide);
}

int RorSolver::slide_node_count() const { return static_cast<int>(m_slide_nodes.size()); }

bool RorSolver::beam_broken(int beam) const {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return false;
    }
    return m_beams[static_cast<size_t>(beam)].broken;
}

float RorSolver::beam_strength(int beam) const {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return 0.0f;
    }
    return m_beams[static_cast<size_t>(beam)].strength;
}

int RorSolver::broken_beam_count() const {
    int count = 0;
    for (const RorBeam &beam : m_beams) {
        if (beam.broken) {
            count += 1;
        }
    }
    return count;
}

void RorSolver::set_node_cab(int node, bool is_cab) {
    if (node < 0 || node >= static_cast<int>(m_nodes.size())) {
        return;
    }
    m_nodes[static_cast<size_t>(node)].cab_node = is_cab;
}

// What a beam does outside the travel it was given. Upstream's `CalcBeams` branches, and the
// reason a rig has suspension rather than springs: a shock is soft over its own travel and
// then hands over to the structure around it.
void RorSolver::apply_bound_law(const RorBeam &beam, float extension, float &spring, float &damping) {
    switch (beam.bound) {
        case BeamBound::NORMAL:
            return;
        case BeamBound::SHOCK1: {
            // How far past a bound the beam is, in metres. Not normalised, so the handover
            // to the structural rates gets firmer the further it is pushed — which is what
            // makes a bump stop feel like one instead of a wall.
            float overshoot = 0.0f;
            if (extension > beam.long_bound * beam.rest_length) {
                overshoot = extension - beam.long_bound * beam.rest_length;
            } else if (extension < -beam.short_bound * beam.rest_length) {
                overshoot = -extension - beam.short_bound * beam.rest_length;
            }
            if (overshoot != 0.0f) {
                spring += (beam.bound_spring - spring) * overshoot;
                damping += (beam.bound_damp - damping) * overshoot;
            }
            return;
        }
        case BeamBound::ROPE:
            // Slack: a rope pushes nothing.
            if (extension < 0.0f) {
                spring = 0.0f;
                damping *= 0.1f;
            }
            return;
        case BeamBound::SUPPORT:
            // Lifted away: a support beam pulls nothing.
            if (extension > 0.0f) {
                spring = 0.0f;
                damping *= 0.1f;
            }
            return;
    }
}

bool RorSolver::set_heightfield(const PackedFloat32Array &heights, int width, int depth,
                                const Vector3 &origin, float spacing) {
    return m_heightfield.set_field(heights, width, depth, origin, spacing);
}

int RorSolver::add_obstacle_box(const Transform3D &transform, const Vector3 &half_extents,
                                int surface) {
    return m_obstacles.add_box(transform, half_extents, surface);
}

void RorSolver::clear_obstacles() {
    m_obstacles.clear();
}

Dictionary RorSolver::obstacle_contact(const Vector3 &position) {
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
    return static_cast<int>(m_obstacles.count());
}

void RorSolver::clear_heightfield() {
    m_heightfield.clear();
}

float RorSolver::ground_height_at(const Vector3 &position) const {
    if (!m_heightfield.enabled()) {
        return m_ground_height;
    }
    return m_heightfield.height_at(position);
}

Vector3 RorSolver::ground_normal_at(const Vector3 &position) const {
    if (!m_heightfield.enabled()) {
        return Vector3(0.0f, 1.0f, 0.0f);
    }
    return m_heightfield.normal_at(position);
}

Vector3 RorSolver::ground_contact_probe(const Vector3 &velocity, const Vector3 &forces, float mass,
                                        float friction_coef, const Vector3 &normal,
                                        float penetration, float dt) const {
    RorNode node;
    node.velocity = velocity;
    node.forces = forces;
    node.mass = mass;
    node.friction_coef = friction_coef;
    // Model 0: the parity comparison is against upstream's default surface.
    return ground_contact_force(node, normal, penetration, dt, m_ground_models[0]);
}

// The world bounds of the rig, grown by the distance it could travel inside one call, handed to
// the obstacle list as its broad phase.
void RorSolver::select_nearby_obstacles() {
    if (m_obstacles.count() == 0) {
        return;
    }
    Vector3 min(1e30f, 1e30f, 1e30f);
    Vector3 max(-1e30f, -1e30f, -1e30f);
    for (const RorNode &node : m_nodes) {
        min.x = std::min(min.x, node.position.x);
        min.y = std::min(min.y, node.position.y);
        min.z = std::min(min.z, node.position.z);
        max.x = std::max(max.x, node.position.x);
        max.y = std::max(max.y, node.position.y);
        max.z = std::max(max.z, node.position.z);
    }
    const Vector3 margin(OBSTACLE_MARGIN_M, OBSTACLE_MARGIN_M, OBSTACLE_MARGIN_M);
    m_obstacles.select(min - margin, max + margin);
}

void RorSolver::apply_ground_contact(float dt) {
    if (!m_ground_enabled || dt <= 0.0f) {
        return;
    }
    const bool sloped = m_heightfield.enabled();
    const Vector3 flat_normal(0.0f, 1.0f, 0.0f);
    for (RorNode &node : m_nodes) {
        if (node.immovable) {
            continue;
        }
        const float ground = sloped ? m_heightfield.height_at(node.position) : m_ground_height;
        const float penetration = ground - static_cast<float>(node.position.y);
        if (penetration < 0.0f) {
            continue;
        }
        node.ground_contact = true;
        // On a slope the reaction has to resolve along the surface, not along the world's
        // vertical: a hill the rig cannot climb and a hill it slides down are both what
        // happens when contact is resolved straight up.
        const Vector3 normal = sloped ? m_heightfield.normal_at(node.position) : flat_normal;
        // Which surface this node is standing on. Per node rather than per rig, so a vehicle
        // straddling the edge of a sand patch has two wheels gripping and two not, which is
        // the whole reason a surface is a map and not a setting.
        size_t model = 0;
        if (m_heightfield.has_surfaces()) {
            const int index = m_heightfield.surface_at(node.position);
            if (index >= 0 && index < static_cast<int>(m_ground_models.size())) {
                model = static_cast<size_t>(index);
            }
        }
        node.forces += ground_contact_force(node, normal, penetration, dt, m_ground_models[model]);
    }
    apply_obstacle_contact(dt);
}

void RorSolver::apply_obstacle_contact(float dt) {
    apply_obstacle_forces(m_nodes, m_obstacles, m_ground_models, dt);
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
        // Measured the way the force law measures it, with upstream's approximate reciprocal
        // square root. An energy function has to be the potential of the force law it
        // accompanies: computing the extension exactly here reports the rig as storing energy
        // at exactly the point the forces call it relaxed, which reads as a rig gaining 6% of
        // its energy from nowhere and staying there at every substep rate.
        const Vector3 separation = m_nodes[beam.a].position - m_nodes[beam.b].position;
        const float squared = static_cast<float>(separation.length_squared());
        if (squared <= 0.0f) {
            continue;
        }
        const float length = squared * fast_invSqrt(squared);
        const float extension = length - beam.rest_length;
        // Through the same bound law the forces go through, for the same reason the length is
        // measured the same way: a slack rope and a lifted support beam exert nothing and so
        // store nothing, and counting their full spring reported this rig as holding twelve
        // times its own energy the moment its suspension was free enough to go slack.
        //
        // For a shock past its travel this is an approximation — the stiffness varies across
        // the overshoot, so the true potential is the integral rather than this product — but
        // it is right at zero and right inside the travel, which is where a settled rig sits.
        float spring = beam.spring;
        float damping = beam.damping;
        apply_bound_law(beam, extension, spring, damping);
        energy += 0.5f * spring * extension * extension;
    }
    return energy;
}

} // namespace rorgd
