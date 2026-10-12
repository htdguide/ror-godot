#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>

// The slide node parity probe: upstream's `SlideNode` on a rig the caller describes, step by step,
// for `the_slide_node_is_upstreams` to compare with upstream's own code in `tools/parity`.

using namespace godot;

namespace rorgd {

// `positions` the nodes, `pairs` the beams as node pairs, `rail` the rail's nodes, `node` the slide
// node, put at `path[i]` before step i with every force cleared. Per step: whether it has broken,
// then every node's force.
PackedFloat32Array RorSolver::slide_probe(const PackedVector3Array &positions, const PackedInt32Array &pairs,
                                          const PackedInt32Array &rail, int node, float spring, float break_force,
                                          float tolerance, const PackedVector3Array &path, float dt) {
    NodeArray nodes(static_cast<size_t>(positions.size()));
    for (int i = 0; i < positions.size(); ++i) {
        nodes[static_cast<size_t>(i)].position = positions[i];
    }
    BeamArray beams(static_cast<size_t>(pairs.size() / 2));
    for (int i = 0; i + 1 < pairs.size(); i += 2) {
        beams[static_cast<size_t>(i / 2)].a = pairs[i];
        beams[static_cast<size_t>(i / 2)].b = pairs[i + 1];
    }
    SlideNodeArray slides(1);
    RorSlideNode &slide = slides[0];
    slide.node = node;
    std::vector<int> rail_nodes;
    for (int i = 0; i < rail.size(); ++i) {
        rail_nodes.push_back(rail[i]);
    }
    build_rail(rail_nodes, beams, slide.rail);
    slide.spring = std::fabs(spring);
    slide.break_force = std::fabs(break_force);
    slide.initial_threshold = slide.threshold = std::fabs(tolerance);
    reset_slide_node(slide, nodes, beams);
    PackedFloat32Array out;
    for (int step = 0; step < path.size(); ++step) {
        nodes[static_cast<size_t>(node)].position = path[step];
        for (RorNode &each : nodes) {
            each.forces = Vector3();
        }
        apply_slide_nodes(slides, nodes, beams, dt);
        out.push_back(slide.broken ? 1.0f : 0.0f);
        for (const RorNode &each : nodes) {
            out.push_back(each.forces.x);
            out.push_back(each.forces.y);
            out.push_back(each.forces.z);
        }
    }
    return out;
}

void RorSolver::bind_slide_methods() {
    ClassDB::bind_static_method("RorSolver",
                                D_METHOD("slide_probe", "positions", "pairs", "rail", "node", "spring", "break_force",
                                         "tolerance", "path", "dt"),
                                &RorSolver::slide_probe);
}

} // namespace rorgd
