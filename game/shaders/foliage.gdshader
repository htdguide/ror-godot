shader_type spatial;
// Vegetation cards that do not read as cards.
//
// A grass or bush card is two crossed quads with a cut-out texture on them, which is what
// upstream draws and what this draws. Four things decide whether that reads as a plant or as a
// sticker, and none of them is the texture:
//
//   - **Normals.** A quad's own normal is flat, so every blade on it shades identically and the
//     card lights up or goes dark as a slab. Real foliage is a rounded mass, so the normal is
//     bent outward from the plant's own axis — the standard foliage trick, and the single
//     biggest difference between "flat" and "planted".
//   - **Translucency.** A leaf lit from behind glows. Godot's backlight term is cheap and is
//     what stops the shaded side of a bush being a black shape.
//   - **Wind.** Nothing in nature is still. The sway is phase-shifted by world position, so a
//     field moves as a field rather than in lockstep.
//   - **Coverage, not cut-out.** Alpha-to-coverage keeps the silhouette's edge soft under MSAA
//     without paying for sorted transparency, and without the crawling edges a hard cut gives.
//
// The colour is varied per instance from the MultiMesh's own instance colour, because a field of
// identically coloured plants is the other half of what reads as fake.

render_mode cull_disabled, depth_prepass_alpha, diffuse_burley;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.35;
// How far the normal is bent away from the card, toward the plant's own rounded shape.
uniform float roundness : hint_range(0.0, 1.0) = 0.75;
// How much light comes through a leaf from behind.
uniform float translucency : hint_range(0.0, 1.0) = 0.35;
uniform vec3 translucency_tint : source_color = vec3(0.55, 0.62, 0.32);
// Wind: how far the top of a plant moves, how fast, and which way.
uniform float sway_m : hint_range(0.0, 1.0) = 0.12;
uniform float sway_speed : hint_range(0.0, 8.0) = 1.4;
uniform vec2 wind_direction = vec2(1.0, 0.3);
// The phase to sway at, instead of the wall clock. Negative means use TIME, which is what a
// window wants; a gate sets a number, because a frame that animates with the wall clock is a
// frame that is different every time it is captured.
//
// This was not a theoretical problem. `ror_terrain_photoset` drifted monotonically through a
// session -- 0.282191, 0.282288, 0.282456 over three runs -- and it was invisible for as long as
// every gate got its own process, because each one started with TIME near zero and landed in the
// same part of the sway. Running the suite in one window made it a real disagreement, and it was
// wrongly written off as renderer warm-up first.
uniform float wind_phase = -1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

varying vec3 plant_normal;

void vertex() {
	// The card's own local y is the plant's height: nothing sways at the root.
	float height = clamp(VERTEX.y, 0.0, 4.0);
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = world.x * 0.7 + world.z * 0.9;
	float clock = wind_phase < 0.0 ? TIME : wind_phase;
	float wave = sin(clock * sway_speed + phase) + 0.4 * sin(clock * sway_speed * 2.3 + phase);
	vec2 push = normalize(wind_direction) * wave * sway_m * height * height;
	VERTEX.xz += push;

	// A rounded normal: away from the plant's own axis, blended with the card's flat one.
	vec3 outward = normalize(vec3(VERTEX.x, max(VERTEX.y, 0.25), VERTEX.z));
	plant_normal = normalize(mix(NORMAL, outward, roundness));
	NORMAL = plant_normal;
}

void fragment() {
	vec4 sampled = texture(albedo_texture, UV);
	ALBEDO = sampled.rgb * COLOR.rgb;
	ALPHA = sampled.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = alpha_cut;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.15;
	BACKLIGHT = translucency_tint * translucency;
	// Both faces of a card are the same leaf, so the normal follows the side being looked at.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
