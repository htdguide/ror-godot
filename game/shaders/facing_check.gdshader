shader_type spatial;
render_mode cull_disabled, unshaded;

// Shows which way a surface faces. The front of a face draws its own texture; the back draws a
// bright colour keyed to the axis the face points along — red for x, green for y, blue for z.
//
// A back face is normally culled, so a wall turned the wrong way is simply absent and a
// photograph of it shows nothing at all. There is no measuring "nothing": the fault and a
// correct empty sky look identical. Painted, the same wall is unmistakable in a still, and a
// gate can count the pixels instead of a person arguing about them.
//
// Unshaded on purpose. The marker has to read the same under any light, at any time of day, from
// any angle, or the measurement becomes a measurement of the lighting.

uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform vec4 albedo_colour : source_color = vec4(1.0);
// How saturated the marker is. The detector asks for a channel spread no natural surface in a
// terrain reaches, so this is not a matter of taste.
uniform float marker_strength : hint_range(0.0, 1.0) = 1.0;
// How wide the magenta bars are, in screen pixels.
const int BAR_PX = 8;

void fragment() {
    if (FRONT_FACING) {
        ALBEDO = texture(albedo_texture, UV).rgb * albedo_colour.rgb;
    } else {
        // The axis the face points along, as a pure primary. A wall facing x shows red from
        // behind, a floor or a roof facing y shows green, a wall facing z shows blue.
        //
        // **In world space.** `NORMAL` in a fragment shader is a *view-space* normal, so a face
        // turned towards the camera is (0, 0, 1) there whatever it is in the world — and every
        // marker in the first set of sheets came out blue, which says only "you are looking at
        // it" and not which wall it is.
        vec3 axis = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
        float strongest = max(axis.x, max(axis.y, axis.z));
        vec3 marker = vec3(
            axis.x >= strongest ? 1.0 : 0.0,
            (axis.y >= strongest && axis.x < strongest) ? 1.0 : 0.0,
            (axis.z >= strongest && axis.x < strongest && axis.y < strongest) ? 1.0 : 0.0
        );
        // **Barred with magenta, because a primary colour is something content has.** A road
        // sign is red, grass is green, and a detector keyed on "a bright saturated channel"
        // counted a correctly drawn warning sign as 34% back-facing. Nothing in a terrain's
        // palette is magenta, so the bars are what the measurement counts and the axis colour
        // between them is what a person reads. In screen space, so the bars stay the same width
        // however far away the surface is and however it is foreshortened.
        float bar = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / float(BAR_PX) * 0.5));
        ALBEDO = mix(marker, vec3(1.0, 0.0, 1.0), bar * marker_strength);
    }
}
