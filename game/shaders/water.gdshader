shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_schlick_ggx;

// A terrain's sea, as a flat plane at the height its own .terrn2 states.
//
// Flat on purpose. A terrain declares `Water` and `WaterLine` and nothing more, so a height is
// all the file gives and a wave is something this project would be inventing. What the shader
// does is make a plane at one height read as water rather than as a sheet of coloured glass: it
// fades where the ground comes up through it, so a beach is a beach instead of a cut line, and
// it holds a specular highlight so the sun is on it.
//
// `depth_draw_never` and a transparent pass, because the ground under the shallows has to show
// through — the depth fade is the whole point and it needs what is behind.
//
// The seam this leaves for later is the one the plan asks for: a height query and a material.
// An FFT surface replaces the vertex displacement and the normal, and nothing above it changes.

// Godot 4 removed the `DEPTH_TEXTURE` builtin in favour of a declared uniform, and a shader
// using the builtin does not compile — it draws nothing at all, silently, which is how this one
// shipped past a gate that was photographing it.
uniform sampler2D depth_buffer : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_colour : source_color = vec3(0.21, 0.42, 0.44);
uniform vec3 deep_colour : source_color = vec3(0.03, 0.09, 0.15);
// How far down, in metres, the water reads as fully deep. A shoreline is a gradient over this.
uniform float depth_fade_m : hint_range(0.1, 40.0) = 6.0;
// How transparent the shallows are where they meet the ground, so a beach shows through.
uniform float edge_clarity : hint_range(0.0, 1.0) = 0.85;
uniform float body_opacity : hint_range(0.0, 1.0) = 0.92;

void fragment() {
    // How much water is between this pixel and whatever is drawn behind it, in metres. The
    // depth texture is the scene's own, so this is the real distance to the sea bed rather than
    // a distance to the plane.
    float behind_raw = texture(depth_buffer, SCREEN_UV).r;
    vec4 behind_view = INV_PROJECTION_MATRIX * vec4(
        SCREEN_UV * 2.0 - 1.0, behind_raw * 2.0 - 1.0, 1.0
    );
    behind_view.xyz /= behind_view.w;
    float through = max(0.0, -behind_view.z - (-VERTEX.z));
    float depth = clamp(through / depth_fade_m, 0.0, 1.0);

    ALBEDO = mix(shallow_colour, deep_colour, depth);
    // Clear at the shoreline, closing up as it deepens: the ground has to come up through it
    // rather than stop at a line.
    ALPHA = mix(1.0 - edge_clarity, body_opacity, depth);
    ROUGHNESS = 0.04;
    METALLIC = 0.0;
    SPECULAR = 0.6;
}
