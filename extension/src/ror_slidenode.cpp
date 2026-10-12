#include "ror_slidenode.h"

#include "ror_ogre_math.h"

#include <algorithm>

using namespace godot;

namespace rorgd {

namespace {

// Upstream's `NearestPointOnLine`: the point on the segment pt1-pt2 nearest `tp`.
Vector3 nearest_point_on_line(const Vector3 &pt1, const Vector3 &pt2, const Vector3 &tp) {
    const Vector3 a = tp - pt1;
    Vector3 b = pt2 - pt1;
    float len = ogre_normalise(b);
    len = std::max(0.0f, std::min(static_cast<float>(a.dot(b)), len));
    return pt1 + b * len;
}

// Upstream's `SlideNode::getLenTo(const beam_t *, point)`.
float length_to(const RorBeam &beam, const NodeArray &nodes, const Vector3 &point) {
    const Vector3 near = nearest_point_on_line(nodes[static_cast<size_t>(beam.a)].position,
                                               nodes[static_cast<size_t>(beam.b)].position, point);
    return static_cast<float>((near - point).length());
}

float length_to(const RorRailSegment &segment, const NodeArray &nodes, const BeamArray &beams, const Vector3 &point) {
    return length_to(beams[static_cast<size_t>(segment.beam)], nodes, point);
}

// Upstream's `RailSegment::CheckCurSlideSegment`: this segment or a neighbour, whichever is nearest.
int check_segment(const std::vector<RorRailSegment> &rail, int current, const NodeArray &nodes,
                  const BeamArray &beams, const Vector3 &point) {
    const RorRailSegment &here = rail[static_cast<size_t>(current)];
    float closest = length_to(here, nodes, beams, point);
    int found = current;
    if (here.prev >= 0) {
        const float distance = length_to(rail[static_cast<size_t>(here.prev)], nodes, beams, point);
        if (distance < closest) {
            found = here.prev;
            closest = distance;
        }
    }
    if (here.next >= 0) {
        const float distance = length_to(rail[static_cast<size_t>(here.next)], nodes, beams, point);
        if (distance < closest) {
            found = here.next;
        }
    }
    return found;
}

// Upstream's `SlideNode::UpdatePosition`.
void update_position(RorSlideNode &slide, const NodeArray &nodes, const BeamArray &beams) {
    const Vector3 at = nodes[static_cast<size_t>(slide.node)].position;
    if (slide.segment < 0 || beams[static_cast<size_t>(slide.rail[static_cast<size_t>(slide.segment)].beam)].broken) {
        slide.ideal = at;
        return;
    }
    slide.segment = check_segment(slide.rail, slide.segment, nodes, beams, at);
    const RorBeam &beam = beams[static_cast<size_t>(slide.rail[static_cast<size_t>(slide.segment)].beam)];
    const Vector3 p1 = nodes[static_cast<size_t>(beam.a)].position;
    Vector3 b = nodes[static_cast<size_t>(beam.b)].position - p1;
    const float length = ogre_normalise(b);
    const float along = static_cast<float>((at - p1).dot(b));
    const float len = std::max(0.0f, std::min(along, length));
    slide.ideal = p1 + b * len;
    slide.ratio = length > 0.0f ? len / length : 0.0f;
}

// Upstream's `SlideNode::UpdateForces` and `CalcCorrectiveForces`. A slide node that breaks still
// pushes on the step it breaks, as upstream's does.
void update_forces(RorSlideNode &slide, NodeArray &nodes, const BeamArray &beams, float dt) {
    if (slide.segment < 0 || slide.broken) {
        return;
    }
    const RorBeam &beam = beams[static_cast<size_t>(slide.rail[static_cast<size_t>(slide.segment)].beam)];
    if (beam.broken) {
        return;
    }
    if (slide.threshold > slide.initial_threshold) {
        slide.threshold -= slide.attach_rate * dt;
    }
    Vector3 force = slide.ideal - nodes[static_cast<size_t>(slide.node)].position;
    const float stretch = std::max(0.0f, ogre_normalise(force) - slide.threshold);
    const Vector3 perp = force * (-slide.spring * stretch);
    if (static_cast<float>(perp.length()) > slide.break_force) {
        slide.broken = true;
    }
    nodes[static_cast<size_t>(slide.node)].forces += -perp;
    nodes[static_cast<size_t>(beam.a)].forces += perp * (1.0f - slide.ratio);
    nodes[static_cast<size_t>(beam.b)].forces += perp * slide.ratio;
}

} // namespace

bool build_rail(const std::vector<int> &rail_nodes, const BeamArray &beams, std::vector<RorRailSegment> &out) {
    out.clear();
    if (rail_nodes.size() < 2) {
        return false;
    }
    for (size_t i = 0; i + 1 < rail_nodes.size(); ++i) {
        int found = -1;
        for (size_t k = 0; k < beams.size(); ++k) {
            const RorBeam &beam = beams[k];
            if ((beam.a == rail_nodes[i] && beam.b == rail_nodes[i + 1]) ||
                (beam.b == rail_nodes[i] && beam.a == rail_nodes[i + 1])) {
                found = static_cast<int>(k);
                break;
            }
        }
        if (found < 0) {
            out.clear();
            return false;
        }
        RorRailSegment segment;
        segment.beam = found;
        out.push_back(segment);
    }
    // Upstream links the middle segments both ways, the end ones inwards, and the ends to each
    // other when the rail closes on itself.
    const int count = static_cast<int>(out.size());
    for (int i = 1; i < count - 1; ++i) {
        out[static_cast<size_t>(i)].prev = i - 1;
        out[static_cast<size_t>(i)].next = i + 1;
    }
    if (count > 1) {
        out[0].next = 1;
        out[static_cast<size_t>(count - 1)].prev = count - 2;
        if (rail_nodes.front() == rail_nodes.back()) {
            out[0].prev = count - 1;
            out[static_cast<size_t>(count - 1)].next = 0;
        }
    }
    return true;
}

void reset_slide_node(RorSlideNode &slide, const NodeArray &nodes, const BeamArray &beams) {
    slide.broken = false;
    if (slide.rail.empty()) {
        slide.segment = -1;
        return;
    }
    // Upstream's `RailGroup::FindClosestSegment`, the first of equals.
    const Vector3 at = nodes[static_cast<size_t>(slide.node)].position;
    float closest = length_to(slide.rail[0], nodes, beams, at);
    int found = 0;
    for (size_t i = 1; i < slide.rail.size(); ++i) {
        const float distance = length_to(slide.rail[i], nodes, beams, at);
        if (distance < closest) {
            closest = distance;
            found = static_cast<int>(i);
        }
    }
    slide.segment = found;
    update_position(slide, nodes, beams);
}

void apply_slide_nodes(SlideNodeArray &slide_nodes, NodeArray &nodes, const BeamArray &beams, float dt) {
    for (RorSlideNode &slide : slide_nodes) {
        update_position(slide, nodes, beams);
        update_forces(slide, nodes, beams, dt);
    }
}

} // namespace rorgd
