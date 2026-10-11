#include "ror_actor_contact.h"

#include <godot_cpp/variant/basis.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace rorgd {

namespace {

// Upstream's ceiling on how many substeps a quiet triangle may skip.
constexpr int MAX_SKIP = 12;
// The back-face vote: the hit node counts three times its neighbours.
constexpr int SELF_WEIGHT = 3;

int sign_of(float value) {
    return value >= 0.0f ? 1 : -1;
}

} // namespace

void RorCollCabs::add(int no, int na, int nb) {
    triangles.push_back(no);
    triangles.push_back(na);
    triangles.push_back(nb);
    rates.emplace_back();
    prepared_nodes = 0;
}

void RorCollCabs::prepare(const NodeArray &nodes, const BeamArray &beams) {
    if (prepared_nodes == nodes.size() && prepared_beams == beams.size()) {
        return;
    }
    // `UpdateCollcabContacterNodes`: a node is contactable when it is on a collision triangle or
    // a rim, and every node is when the actor has no triangles at all.
    contactable.assign(nodes.size(), count() == 0 ? 1 : 0);
    rim.resize(nodes.size(), 0);
    for (int node : triangles) {
        if (node >= 0 && static_cast<size_t>(node) < nodes.size()) {
            contactable[static_cast<size_t>(node)] = 1;
        }
    }
    for (size_t i = 0; i < nodes.size(); ++i) {
        if (rim[i]) {
            contactable[i] = 1;
        }
    }
    // `ar_node_to_node_connections`, from every beam the rig was built with.
    neighbours.assign(nodes.size(), {});
    for (const RorBeam &beam : beams) {
        if (beam.a < 0 || beam.b < 0 || static_cast<size_t>(beam.a) >= nodes.size() ||
            static_cast<size_t>(beam.b) >= nodes.size()) {
            continue;
        }
        neighbours[static_cast<size_t>(beam.a)].push_back(beam.b);
        neighbours[static_cast<size_t>(beam.b)].push_back(beam.a);
    }
    prepared_nodes = nodes.size();
    prepared_beams = beams.size();
}

void reset_rates(RorCollCabs &cabs) {
    for (RorCollCabRate &rate : cabs.rates) {
        rate.rate = 0;
    }
}

int resolve_inter_actor(RorCollCabs &owner_cabs, NodeArray &owner_nodes,
                        const RorGroundModel &surface, const RorCollCabs &other_cabs,
                        NodeArray &other_nodes, const Vector3 &other_to_owner, float dt) {
    const float range = owner_cabs.range;
    // The other actor's contactable nodes, in the owner's frame, kept only if they are anywhere
    // near the owner's triangles at all. Upstream's k-d tree answers each triangle's query over
    // every partner node; this narrows the set once per substep so the per-triangle test runs
    // over the handful of nodes actually close, and is exact because a node outside the union of
    // the triangles' padded boxes cannot be inside any one of them.
    Vector3 low(1e30f, 1e30f, 1e30f);
    Vector3 high(-1e30f, -1e30f, -1e30f);
    for (int node : owner_cabs.triangles) {
        const Vector3 &p = owner_nodes[static_cast<size_t>(node)].position;
        low = low.min(p);
        high = high.max(p);
    }
    const Vector3 pad(range, range, range);
    low -= pad;
    high += pad;
    std::vector<int> near;
    std::vector<Vector3> near_at;
    for (size_t i = 0; i < other_nodes.size(); ++i) {
        if (i >= other_cabs.contactable.size() || !other_cabs.contactable[i]) {
            continue;
        }
        const Vector3 p = other_nodes[i].position + other_to_owner;
        if (p.x < low.x || p.y < low.y || p.z < low.z || p.x > high.x || p.y > high.y ||
            p.z > high.z) {
            continue;
        }
        near.push_back(static_cast<int>(i));
        near_at.push_back(p);
    }

    int contacts = 0;
    for (size_t t = 0; t < owner_cabs.count(); ++t) {
        RorCollCabRate &rate = owner_cabs.rates[t];
        if (rate.rate > 0) {
            rate.distance++;
            rate.rate--;
            continue;
        }
        rate.rate = std::min(rate.distance, MAX_SKIP);
        rate.distance = 0;

        RorNode &no = owner_nodes[static_cast<size_t>(owner_cabs.triangles[t * 3])];
        RorNode &na = owner_nodes[static_cast<size_t>(owner_cabs.triangles[t * 3 + 1])];
        RorNode &nb = owner_nodes[static_cast<size_t>(owner_cabs.triangles[t * 3 + 2])];
        // `PointColDetector::query(no, na, nb, collrange)`: the triangle's box, padded.
        const Vector3 box_low = no.position.min(na.position).min(nb.position) - pad;
        const Vector3 box_high = no.position.max(na.position).max(nb.position) + pad;
        bool queried = false;
        bool built = false;
        Basis to_triangle;
        Vector3 normal;
        for (size_t h = 0; h < near.size(); ++h) {
            const Vector3 &p = near_at[h];
            if (p.x < box_low.x || p.y < box_low.y || p.z < box_low.z || p.x > box_high.x ||
                p.y > box_high.y || p.z > box_high.z) {
                continue;
            }
            queried = true;
            if (!built) {
                // `Triangle(na, nb, no)` and `CartesianToTriangleTransform`: spans from `no`,
                // the normal their cross product, and the inverse of [u v n].
                const Vector3 u = na.position - no.position;
                const Vector3 v = nb.position - no.position;
                normal = u.cross(v).normalized();
                Basis spans;
                spans.set_column(0, u);
                spans.set_column(1, v);
                spans.set_column(2, normal);
                to_triangle = spans.inverse();
                built = true;
            }
            const Vector3 local = to_triangle.xform(p - no.position);
            const float alpha = static_cast<float>(local.x);
            const float beta = static_cast<float>(local.y);
            const float gamma = 1.0f - alpha - beta;
            float distance = static_cast<float>(local.z);
            if (alpha < 0.0f || beta < 0.0f || gamma < 0.0f || std::abs(distance) > range) {
                continue;
            }
            rate.rate = 0;
            const int hit_index = near[h];
            RorNode &hit = other_nodes[static_cast<size_t>(hit_index)];

            // `BackfaceCollisionTest`: which side the hit node and its neighbours are mostly on.
            Vector3 facing = normal;
            int vote = SELF_WEIGHT * sign_of(distance);
            const std::vector<int> &around = other_cabs.neighbours[static_cast<size_t>(hit_index)];
            if (around.size() > static_cast<size_t>(SELF_WEIGHT)) {
                for (int id : around) {
                    const Vector3 at = other_nodes[static_cast<size_t>(id)].position + other_to_owner;
                    vote += sign_of(static_cast<float>(facing.dot(at - no.position)));
                }
            }
            if (vote < 0) {
                facing = -facing;
                distance = -distance;
            }
            const float penetration = range - distance;

            // `ResolveCollisionForces`: the ground's law on the velocity relative to the
            // triangle and the pair's reduced mass, given to the node and taken back from the
            // triangle's corners in proportion to where on it the node struck.
            const Vector3 velocity =
                    hit.velocity - (na.velocity * alpha + nb.velocity * beta + no.velocity * gamma);
            const float triangle_mass = na.mass * alpha + nb.mass * beta + no.mass * gamma;
            const float mass = (hit.mass * triangle_mass) / (hit.mass + triangle_mass);
            const Vector3 force =
                    ground_contact_force(hit, velocity, mass, facing, penetration, dt, surface);
            hit.forces += force;
            na.forces -= force * alpha;
            nb.forces -= force * beta;
            no.forces -= force * gamma;
            ++contacts;
        }
        if (!queried) {
            rate.rate++;
        }
    }
    return contacts;
}

} // namespace rorgd
