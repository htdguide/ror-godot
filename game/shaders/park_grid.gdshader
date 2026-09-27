shader_type spatial;
// The test park's dev grid, drawn procedurally rather than painted into the terrain's colour map.
//
// The colour map holds one texel per metre and is sampled with a filter and mipmaps, so a 0.45 m
// line is a third of a texel and arrives as a smear: a session reported the grid as "too blurry",
// and no line width or palette fixes that, because the resolution is the problem.
//
// Here the line is a function of the world position instead, so it is exactly as sharp as the
// pixel it lands in at any distance. `coverage` is analytic anti-aliasing: the width of one
// pixel in world metres is `fwidth`, and a line narrower than that returns partial coverage
// rather than flickering in and out between frames.
//
// The grid is an overlay above the ground, not the ground: the terrain still draws the base
// colour and every surface a test area is made of. Where a test area is, this discards — and
// which points those are is not decided here. It is baked from `ParkShape` into a mask, so the
// one place that knows where the road is stays the one place that knows.

render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform float spacing_m = 5.0;
uniform float line_width_m = 0.45;
uniform float major_every = 10.0;
// A major line is drawn wider as well as brighter, the way a drawing's major division is.
uniform float major_width_scale = 1.8;
uniform vec3 line_colour : source_color = vec3(0.46, 0.49, 0.54);
uniform vec3 major_colour : source_color = vec3(0.62, 0.70, 0.80);
uniform float grid_roughness = 0.9;
// 1 where the ground is grid, 0 where a test area is drawn as itself.
uniform sampler2D test_area_mask : filter_linear, repeat_disable, hint_default_white;
// The mask's first texel centre, and how many metres the mask spans.
uniform vec2 mask_origin_m = vec2(-1024.5, -1024.5);
uniform float mask_size_m = 2048.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How much of this pixel a line at every `spacing` metres covers, anti-aliased.
float coverage(float along, float spacing, float width) {
	float distance_m = abs(fract(along / spacing + 0.5) - 0.5) * spacing;
	float pixel_m = max(fwidth(along), 0.00001);
	return clamp((width * 0.5 + pixel_m - distance_m) / (2.0 * pixel_m), 0.0, 1.0);
}

void fragment() {
	vec2 ground = world_position.xz;
	vec2 mask_uv = (ground - mask_origin_m) / mask_size_m;
	if (texture(test_area_mask, mask_uv).r < 0.5) {
		discard;
	}
	float minor = max(
		coverage(ground.x, spacing_m, line_width_m),
		coverage(ground.y, spacing_m, line_width_m)
	);
	float major_spacing = spacing_m * major_every;
	float major_width = line_width_m * major_width_scale;
	float major = max(
		coverage(ground.x, major_spacing, major_width),
		coverage(ground.y, major_spacing, major_width)
	);
	float alpha = max(minor, major);
	if (alpha <= 0.002) {
		discard;
	}
	ALBEDO = mix(line_colour, major_colour, major);
	ALPHA = alpha;
	ROUGHNESS = grid_roughness;
}
