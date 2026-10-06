shader_type sky;
// A sky photographed rather than modelled: one high-dynamic-range panorama of a real sky, used
// both as the picture behind the scene and as the light in front of it.
//
// **This is the sky the project can be graded against.** A modelled sky states a look and the
// light follows from whatever its colours integrate to; a captured one carries the balance the
// place had — `daylight_shadows_are_readable` has recorded for as long as it has existed that
// this scene's sun-to-sky ratio was a number somebody chose rather than one daylight produced.
// Godot's own `PanoramaSkyMaterial` would draw the picture, and this shader exists for the two
// things it cannot do: take the sun out of the light without taking it out of the picture, and
// hand the exposure back on the pass the engine exposes twice.

// The panorama, in equirectangular layout: longitude across, latitude down.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// What the map is worth as light. A Poly Haven sky is normalised so its *picture* reads well —
// the mean of the clear afternoon's sky is 1.56 and the overcast one's 1.23, which says nothing
// about either being a hundred thousand lux or fifteen — so an hour states what its own map is
// worth and `the_sky_balances_against_daylight` is what the number is set from.
uniform float energy = 1.0;
// How much of that brightness reaches the radiance map every surface is lit from, as against how
// much of it is seen. A night sky is drawn to be looked at and lights almost nothing.
uniform float radiance_scale = 1.0;
// **The sun in the map is not the sun in the scene.** Measured over the four maps this project
// ships, the solar disc of the clear afternoon is 80 pixels of a two-megapixel map and 91% of all
// the light in it; the moon in the night map is 47 pixels and 86%. A scene lit by both that disc
// and its own `DirectionalLight3D` is lit by two suns, and the one in the map casts no shadow.
// So the radiance pass sees the sky with the disc taken out of it, and the picture keeps it.
uniform float radiance_clamp = 50.0;
// How much of the camera's own exposure the engine will apply to this sky twice over.
//
// The light a sky gives is exposed once when the radiance map is rendered and again when the
// scene is lit from it, while a lamp is exposed once — measured, a surface lit only by the sky
// brightened four times for twice the ISO where one lit by the sun brightened twice. The cube-map
// pass gives it back. See `PhysicalCamera.exposure_scale` and `sky_clouds.gdshader`, which
// carries the same correction for the modelled sky.
uniform float light_exposure = 1.0;


void sky() {
	vec3 direction = normalize(EYEDIR);
	// Godot's own panorama convention, from `sky_material.cpp`: longitude from `atan(x, z)`
	// running the other way, latitude from `acos(y)` down the image.
	vec2 uv = vec2(atan(direction.x, direction.z), acos(clamp(direction.y, -1.0, 1.0)));
	uv /= vec2(-2.0 * PI, PI);
	uv += vec2(0.5, 0.0);
	vec3 colour = texture(panorama, uv).rgb;
	if (AT_CUBEMAP_PASS) {
		colour = min(colour, vec3(radiance_clamp)) * radiance_scale
			/ max(light_exposure, 0.000001);
	}
	COLOR = colour * energy;
}
