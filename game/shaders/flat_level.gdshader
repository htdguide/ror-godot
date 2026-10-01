// A surface of one exact linear value, for calibrating a capture.
//
// `StandardMaterial3D.albedo_color` is treated as sRGB and converted on the way in, so asking it
// for 4.0 puts 25.3 on screen. A measurement of the capture path has to inject a number nothing
// transforms, which is what this is: one uniform, straight into ALBEDO, unshaded.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float level = 1.0;

void fragment() {
	ALBEDO = vec3(level);
}
