#include "ror_flex.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace rorgd {

void RorFlex::_bind_methods() {
    ClassDB::bind_method(D_METHOD("version"), &RorFlex::version);
    ClassDB::bind_method(D_METHOD("triad_transform", "nodes", "ref", "nx", "ny", "center"),
                         &RorFlex::triad_transform);
    ClassDB::bind_method(D_METHOD("deform_vertex", "nodes", "ref", "nx", "ny", "coords", "center"),
                         &RorFlex::deform_vertex);
    ClassDB::bind_method(D_METHOD("bind_coords", "nodes", "ref", "nx", "ny", "vertex"),
                         &RorFlex::bind_coords);
}

String RorFlex::version() const {
    return String("rorbridge ") + String(__DATE__) + String(" ") + String(__TIME__);
}

Transform3D RorFlex::triad_transform(const PackedVector3Array &nodes, int ref, int nx, int ny,
                                     const Vector3 &center) const {
    const Vector3 origin = nodes[ref];
    const Vector3 diff_x = nodes[nx] - origin;
    const Vector3 diff_y = nodes[ny] - origin;
    const Vector3 n_cross = diff_x.cross(diff_y).normalized();
    // Basis columns, matching upstream's use of the three vectors as an oblique frame.
    Basis basis;
    basis.set_column(0, diff_x);
    basis.set_column(1, diff_y);
    basis.set_column(2, n_cross);
    return Transform3D(basis, origin - center);
}

Vector3 RorFlex::deform_vertex(const PackedVector3Array &nodes, int ref, int nx, int ny,
                               const Vector3 &coords, const Vector3 &center) const {
    return triad_transform(nodes, ref, nx, ny, center).xform(coords);
}

Vector3 RorFlex::bind_coords(const PackedVector3Array &nodes, int ref, int nx, int ny,
                             const Vector3 &vertex) const {
    const Transform3D frame = triad_transform(nodes, ref, nx, ny, Vector3());
    return frame.affine_inverse().xform(vertex);
}

} // namespace rorgd
