#pragma once

#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// The ground the rig stands on, as a grid of heights.
//
// The solver cannot ask the terrain a question per node per substep: at 2 kHz with hundreds
// of nodes that is millions of calls a second across the scripting boundary, and the terrain
// would become the simulation's cost. So the heights are copied in once, in bulk, and sampled
// here in C++ — which is also exactly how Terrain3D's own data is laid out, one image per
// region, so the copy is a copy and not a conversion.
//
// A flat plane is the degenerate case and stays the default: a rig has to be able to run with
// no terrain at all, because most gates do.
class RorHeightfield {
public:
    // `heights` is row-major, `depth` rows of `width` columns, sampled every `spacing` metres
    // starting at `origin`. Returns false if the dimensions do not match the data.
    bool set_field(const godot::PackedFloat32Array &heights, int width, int depth,
                   const godot::Vector3 &origin, float spacing);
    void clear();
    bool enabled() const { return m_enabled; }
    int width() const { return m_width; }
    int depth() const { return m_depth; }

    // Ground height under a world position, bilinearly interpolated. Positions outside the
    // field clamp to its edge rather than falling through it.
    float height_at(const godot::Vector3 &position) const;
    // Surface normal there, from the height gradient. A sloped contact needs this: the whole
    // point of ground contact is that it resolves along the surface normal, and on a slope
    // straight up is the wrong answer.
    godot::Vector3 normal_at(const godot::Vector3 &position) const;

private:
    float sample(int x, int z) const;

    std::vector<float> m_heights;
    int m_width = 0;
    int m_depth = 0;
    godot::Vector3 m_origin;
    float m_spacing = 1.0f;
    bool m_enabled = false;
};

} // namespace rorgd
