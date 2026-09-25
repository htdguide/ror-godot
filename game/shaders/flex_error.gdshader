shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
// Measures, on the GPU, how far Godot's skinning result lands from the CPU reference.
//
// VERTEX inside vertex() is already skinned: Godot applies the bone matrices before user
// vertex code. CUSTOM0 carries the CPU-side FlexBody result for the same vertex, and is
// not skinned, so the difference between them is exactly the error the spike is after.
//
// Red is a plain over-threshold flag, which survives any colour-space handling and so
// cannot be argued with. Green encodes the error against the threshold so a number can be
// read back. Blue is a constant presence marker: without it a perfect result paints black
// and is indistinguishable from nothing rendering at all, which would let the gate pass
// by failing to draw.

uniform float threshold_mm = 1.0;
const float METRES_TO_MM = 1000.0;

varying float v_error_mm;

uniform float point_size = 5.0;

void vertex() {
    POINT_SIZE = point_size;
    vec3 reference = CUSTOM0.xyz;
    v_error_mm = length(VERTEX - reference) * METRES_TO_MM;
}

void fragment() {
    float ratio = v_error_mm / threshold_mm;
    ALBEDO = vec3(step(1.0, ratio), clamp(ratio, 0.0, 1.0), 1.0);
}
