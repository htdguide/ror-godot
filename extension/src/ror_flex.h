#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace rorgd {

// Rigs of Rods' FlexBody deformation, in C++, on the Godot side of the bridge.
//
// This is the same maths the GDScript reference implements, kept in both languages on
// purpose: the flexbody_cpp_parity gate requires them to agree exactly, so the readable
// GDScript version stays a trustworthy description of what actually runs.
//
// From FlexBody::computeFlexbody() upstream, per vertex:
//     diffX  = P[nx] - P[ref]
//     diffY  = P[ny] - P[ref]
//     nCross = normalize(diffX x diffY)
//     dst    = diffX*c.x + diffY*c.y + nCross*c.z + P[ref] - center
class RorFlex : public godot::RefCounted {
    GDCLASS(RorFlex, godot::RefCounted)

protected:
    static void _bind_methods();

public:
    // Build identity, so a loaded binary can be told apart from a stale one.
    godot::String version() const;

    // The locator triad's frame. Deliberately non-orthonormal: its columns carry the
    // stretch and shear of the node triangle, which is what makes the deformation soft.
    godot::Transform3D triad_transform(const godot::PackedVector3Array &nodes, int ref, int nx,
                                       int ny, const godot::Vector3 &center) const;

    // One vertex, deformed.
    godot::Vector3 deform_vertex(const godot::PackedVector3Array &nodes, int ref, int nx, int ny,
                                 const godot::Vector3 &coords, const godot::Vector3 &center) const;

    // Bind-space coordinates for a vertex, as the upstream spawner computes them:
    // coords = F_bind^-1 * (vertex - P[ref]).
    godot::Vector3 bind_coords(const godot::PackedVector3Array &nodes, int ref, int nx, int ny,
                               const godot::Vector3 &vertex) const;
};

} // namespace rorgd
