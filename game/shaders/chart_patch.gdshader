// A patch of exactly known linear reflectance, for photographing.
//
// `StandardMaterial3D.albedo_color` is treated as sRGB and converted on the way in, so a patch
// asked for 0.18 is not an 18% grey card. This takes the reflectance straight into ALBEDO.
//
// Lambert and no specular, because a grey card is a diffuse reflector and the measurement is of
// the light falling on it, not of a highlight.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 reflectance = vec3(0.18);

void fragment() {
	ALBEDO = reflectance;
	ROUGHNESS = 1.0;
}
