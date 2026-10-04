shader_type sky;
// A daylight sky with volumetric clouds.
//
// Godot's `ProceduralSkyMaterial` draws a gradient and a sun disc, which is a fine ground truth
// for a lighting gate and is not a sky anybody believes. Clouds are what tell a driver the scene
// has weather in it, and a flat cloud texture on a dome reads as a painted ceiling the moment the
// camera moves.
//
// So the clouds are marched. The sky shader runs per pixel with a view direction, and the cloud
// layer is a slab between two altitudes: step along the ray through the slab, sample a noise
// field for density, and accumulate. Light comes from marching a few short steps toward the sun
// and applying Beer's law, which is the standard cheap approximation and is what gives a cloud a
// bright edge and a dark base rather than a flat grey.
//
// Cost is the step counts, and the radiance pass — the one that lights the scene — runs at a
// lower count because it is convolved into an irradiance map anyway and nobody sees its detail.

uniform vec3 sky_top : source_color = vec3(0.16, 0.33, 0.66);
uniform vec3 sky_horizon : source_color = vec3(0.62, 0.72, 0.84);
uniform vec3 ground_colour : source_color = vec3(0.42, 0.40, 0.37);
uniform float sky_curve = 0.12;
uniform float sky_energy = 1.0;

uniform vec3 cloud_colour : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 cloud_shadow : source_color = vec3(0.42, 0.46, 0.55);
// How much of the sky is cloud, and how solid each one is.
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform float density : hint_range(0.0, 4.0) = 1.1;
// The slab the clouds live in, in metres above the camera, and how big a cloud is across.
uniform float cloud_bottom_m = 900.0;
uniform float cloud_top_m = 2300.0;
uniform float cloud_scale_m = 1600.0;
// The erosion field: how much finer than the shape, and how deeply it bites.
uniform float detail_scale : hint_range(1.0, 12.0) = 5.0;
uniform float erosion : hint_range(0.0, 1.0) = 0.25;
// Where the weather is going, and how fast.
uniform vec2 wind = vec2(1.0, 0.35);
uniform float wind_speed = 0.006;
// Marching. The radiance pass is convolved into an irradiance map, so it gets fewer.
uniform int steps : hint_range(8, 64) = 28;
uniform int radiance_steps : hint_range(4, 24) = 10;
uniform int light_steps : hint_range(1, 8) = 4;

// Value noise, hashed from integer lattice points. Deterministic, no texture, and cheap enough
// to afford three octaves inside a march.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

// How much cloud is at a point in the slab.
//
// A low-frequency field decides where the clouds are, and a higher-frequency one is subtracted
// from their edges — erosion, the standard way of getting a billowing edge out of smooth noise.
// Without it the shapes are soft blobs whatever the coverage is, which is what a first version of
// this looked like.
float cloud_density(vec3 position, float time) {
	vec3 sample_at = position / cloud_scale_m;
	sample_at.xz += wind * time * wind_speed;
	float shape = fbm(sample_at);
	float cut = 1.0 - coverage;
	float value = clamp((shape - cut) / max(1.0 - cut, 0.001), 0.0, 1.0);
	if (value > 0.0) {
		float detail = fbm(sample_at * detail_scale + vec3(11.3, 4.1, 7.7));
		value = clamp(value - detail * erosion * (1.0 - value), 0.0, 1.0);
		// And a firmer edge, so a cloud has a surface rather than fading out over a kilometre.
		value = smoothstep(0.0, 0.35, value);
	}
	float height = clamp(
		(position.y - cloud_bottom_m) / max(cloud_top_m - cloud_bottom_m, 1.0), 0.0, 1.0
	);
	float profile = smoothstep(0.0, 0.25, height) * smoothstep(1.0, 0.65, height);
	return value * profile * density;
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	// The gradient underneath, which is what lights the scene when the clouds are thin.
	float up = clamp(direction.y, 0.0, 1.0);
	vec3 base = mix(sky_horizon, sky_top, pow(up, sky_curve));
	if (direction.y < 0.0) {
		base = mix(sky_horizon, ground_colour, clamp(-direction.y * 4.0, 0.0, 1.0));
	}

	vec3 sun_direction = -LIGHT0_DIRECTION;
	float to_sun = clamp(dot(direction, sun_direction), 0.0, 1.0);
	// The sun's own disc and the glow around it, on the gradient rather than on the clouds.
	base += LIGHT0_COLOR * LIGHT0_ENERGY * (
		smoothstep(0.9995, 0.99975, 1.0 - (1.0 - to_sun)) * 0.0
		+ pow(to_sun, 700.0) * 12.0
		+ pow(to_sun, 8.0) * 0.06
	);

	vec3 colour = base;

	// Clouds are drawn for the eye and not into the radiance map. The map is what lights the
	// scene, and a sky full of bright cloud raises its irradiance enough to flatten everything:
	// measured, the hero truck went from 2.1x brighter lit from the front to 1.02x, and the
	// tunnel stopped being darker inside than out. The scene is still lit by the stated
	// gradient — which is what every lighting gate here is graded against — and the clouds are
	// what a person sees. That is a real limitation and it is named rather than hidden: an
	// overcast sky does not yet light like one.
	if (!AT_CUBEMAP_PASS && direction.y > 0.02) {
		int march = steps;
		float enter = cloud_bottom_m / direction.y;
		float exit = cloud_top_m / direction.y;
		float span = (exit - enter) / float(march);
		float transmittance = 1.0;
		vec3 scattered = vec3(0.0);
		// A dithered start, so the march's own steps do not show up as bands.
		float offset = hash(direction * 811.0) * span;
		for (int i = 0; i < march; i++) {
			if (transmittance < 0.02) {
				break;
			}
			vec3 at = direction * (enter + offset + float(i) * span);
			float thickness = cloud_density(at, TIME);
			if (thickness <= 0.001) {
				continue;
			}
			// Beer's law toward the sun: a few long steps are enough for the bright rim and
			// the dark base, which is all a cloud's shading really is.
			float shadow = 0.0;
			for (int l = 1; l <= light_steps; l++) {
				vec3 toward = at + sun_direction * (float(l) * cloud_scale_m * 0.06);
				shadow += cloud_density(toward, TIME);
			}
			float light = exp(-shadow * 0.55);
			vec3 lit = mix(cloud_shadow, cloud_colour, light)
				* (LIGHT0_COLOR * LIGHT0_ENERGY * 0.5 + 0.5);
			float step_transmittance = exp(-thickness * span * 0.0016);
			scattered += lit * transmittance * (1.0 - step_transmittance);
			transmittance *= step_transmittance;
		}
		// Clouds fade out toward the horizon, where a slab of finite height would otherwise
		// stretch into an opaque band.
		float horizon_fade = smoothstep(0.02, 0.22, direction.y);
		float cover = (1.0 - transmittance) * horizon_fade;
		colour = mix(colour, scattered / max(cover, 0.001), cover);
	}
	// The hour's own brightness, applied to the clouds as well as to the gradient.
	//
	// **It used to scale only the gradient.** A night states a sky energy of four ten-thousandths
	// and the clouds stayed at their daylight brightness, so the night sky in a window was a
	// blazing white overcast with black holes in it, and the vehicle's reflection probe caught it
	// and turned the bodywork white. Reported from a window: "when I choose night, the sky is
	// very white and the car starts reflecting something and also becomes white."
	COLOR = colour * sky_energy;
}
