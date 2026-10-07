#include "ror_slidenode.h"

#include <cmath>

using namespace godot;

namespace rorgd {

namespace {

// Where on the segment a-b the point lies, as a fraction clamped to the segment's own ends, and
// the point itself. Upstream walks the rail's segments and keeps the nearest; a hub at the end of
// its travel has to stop there rather than carry on up an imaginary extension of the rail.
struct OnSegment {
    float along = 0.0f;
    Vector3 point;
    float distance_sq = 0.0f;
};

OnSegment closest_on(const Vector3 &a, const Vector3 &b, const Vector3 &point) {
    OnSegment out;
    const Vector3 span = b - a;
    const float length_sq = span.length_squared();
    out.along = length_sq > 0.0f ? (point - a).dot(span) / length_sq : 0.0f;
    out.along = out.along < 0.0f ? 0.0f : (out.along > 1.0f ? 1.0f : out.along);
    out.point = a + span * out.along;
    out.distance_sq = out.point.distance_squared_to(point);
    return out;
}

} // namespace

void apply_slide_nodes(SlideNodeArray &slide_nodes, NodeArray &nodes) {
    const int node_count = static_cast<int>(nodes.size());
    for (RorSlideNode &slide : slide_nodes) {
        if (slide.broken || slide.rail.size() < 2 || slide.node < 0 || slide.node >= node_count) {
            continue;
        }
        const Vector3 at = nodes[slide.node].position;

        // The nearest segment of the rail, and where on it the node sits.
        int best = -1;
        OnSegment found;
        for (size_t i = 0; i + 1 < slide.rail.size(); ++i) {
            const int a = slide.rail[i];
            const int b = slide.rail[i + 1];
            if (a < 0 || b < 0 || a >= node_count || b >= node_count) {
                continue;
            }
            const OnSegment here = closest_on(nodes[a].position, nodes[b].position, at);
            if (best < 0 || here.distance_sq < found.distance_sq) {
                best = static_cast<int>(i);
                found = here;
            }
        }
        if (best < 0) {
            continue;
        }

        // Pulled towards that point, with the tolerance subtracted: inside it the node is free
        // to move along the rail and nothing acts.
        Vector3 toward = found.point - at;
        const float distance = toward.length();
        const float past = distance - slide.tolerance;
        if (distance <= 0.0f || past <= 0.0f) {
            continue;
        }
        const Vector3 force = toward / distance * (slide.spring * past);
        if (slide.break_force > 0.0f && force.length() > slide.break_force) {
            slide.broken = true;
            continue;
        }
        // The reaction goes onto the segment, shared by where along it the point fell: a node
        // near one end leans on that end.
        nodes[slide.node].forces += force;
        nodes[slide.rail[best]].forces -= force * (1.0f - found.along);
        nodes[slide.rail[best + 1]].forces -= force * found.along;
    }
}

} // namespace rorgd
