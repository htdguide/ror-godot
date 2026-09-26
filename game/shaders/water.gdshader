shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
// The staged water surface: depth-faded, with two scrolling ripple layers.
//
// The depth of the water under each vertex is baked into the mesh by world/valley_water.gd and
// arrives in COLOR.r, rather than being reconstructed here from the depth buffer. The mesh is
// generated from the same functions that carved the bed, so the depth is known exactly and
// needs no reconstruction; the cost of that choice is that the fade does not respond to
// anything the terrain did not put there — a truck standing in the ford is not faded around.
// That is the M6/M8 work, which replaces this with screen-space reflection and an FFT surface
// behind the same material interface. Refraction waits for the same milestone: bending the view
// of the bed needs the screen texture, which needs this surface in the transparent queue after
// everything it refracts, and getting that ordering right is worth doing once, with SSR.

uniform vec4 shallow_colour : source_color;
uniform vec4 deep_colour : source_color;
uniform float fade_depth_m = 2.5;
uniform float edge_depth_m = 0.35;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_scale_m = 6.0;
uniform float ripple_scale_fine_m = 1.7;
uniform vec2 ripple_drift = vec2(0.09, 0.05);
uniform vec2 ripple_drift_fine = vec2(-0.05, 0.11);
uniform float ripple_strength = 0.35;
uniform float water_roughness = 0.06;
uniform float water_specular = 0.5;

varying vec3 world_position;
varying float water_depth_m;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // COLOR.r is the depth as a fraction of fade_depth_m: vertex colour is eight bits a channel,
    // so a depth baked in metres would be clamped at one metre.
    water_depth_m = COLOR.r * fade_depth_m;
}

void fragment() {
    // Two layers at different scales drifting in different directions. One layer alone reads as
    // a sheet sliding over the surface, because every ripple on it moves the same way.
    vec2 coarse = world_position.xz / ripple_scale_m + ripple_drift * TIME;
    vec2 fine = world_position.xz / ripple_scale_fine_m + ripple_drift_fine * TIME;
    vec3 ripple = texture(ripples, coarse).rgb * 2.0 - 1.0;
    ripple += texture(ripples, fine).rgb * 2.0 - 1.0;
    NORMAL_MAP = normalize(vec3(ripple.xy * ripple_strength, 1.0)) * 0.5 + 0.5;

    float depth_mix = clamp(water_depth_m / fade_depth_m, 0.0, 1.0);
    ALBEDO = mix(shallow_colour.rgb, deep_colour.rgb, depth_mix);
    // Transparent at the water's edge and nearly opaque where it is deep: the bed shows through
    // the shallows, which is what a shoreline is made of.
    ALPHA = clamp(water_depth_m / edge_depth_m, 0.0, 1.0) * mix(0.55, 0.95, depth_mix);
    ROUGHNESS = water_roughness;
    SPECULAR = water_specular;
    METALLIC = 0.0;
}
