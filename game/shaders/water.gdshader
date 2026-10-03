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
uniform float depth_fade_m : hint_range(0.1, 40.0) = 2.5;
// How transparent the shallows are where they meet the ground, so a beach shows through.
uniform float edge_clarity : hint_range(0.0, 1.0) = 0.85;
uniform float body_opacity : hint_range(0.0, 1.0) = 1.0;
// How big the ripples are across the surface, in metres, and how steep.
uniform float ripple_m : hint_range(0.2, 20.0) = 2.6;
uniform float ripple_steepness : hint_range(0.0, 1.0) = 0.22;
// What the surface reflects where it is edge-on to the eye.
uniform vec3 sky_tint : source_color = vec3(0.55, 0.66, 0.78);

// Three crossing waves, as a height field. Static, not animated: a gate captures two frames
// twelve apart and requires them identical, and a surface that moves with TIME is a surface no
// capture can be compared against. Movement belongs with the FFT solver, behind a flag.
float swell(vec2 at) {
    float h = sin(at.x * 1.00 + at.y * 0.35);
    h += 0.7 * sin(at.x * -0.45 + at.y * 1.10 + 1.7);
    h += 0.45 * sin(at.x * 0.80 + at.y * -0.95 + 3.1);
    return h * 0.43;
}

void fragment() {
    // How much water is between this pixel and whatever is drawn behind it, in metres.
    //
    // **The depth value is already NDC z.** Remapping it with `* 2.0 - 1.0`, as an OpenGL-era
    // snippet does, puts the sea bed at the wrong distance and everything reads as shallow — so
    // the whole sea drew at its shoreline alpha and you could see the bottom through all of it.
    float behind_raw = texture(depth_buffer, SCREEN_UV).r;
    vec4 behind_view = INV_PROJECTION_MATRIX * vec4(
        SCREEN_UV * 2.0 - 1.0, behind_raw, 1.0
    );
    behind_view.xyz /= behind_view.w;
    float through = max(0.0, -behind_view.z - (-VERTEX.z));
    float depth = clamp(through / depth_fade_m, 0.0, 1.0);

    // **Ripples, because a flat mirror reflects the sun as one egg.** A real sea breaks the
    // sun's reflection into a long glitter path, and what breaks it is the slope of the water
    // rather than its colour. Sampled in world metres so the scale does not change with the
    // camera, and differenced rather than stored, which is a normal map without a texture.
    vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 at = world.xz / ripple_m;
    float step_m = 0.35;
    vec3 slope = normalize(vec3(
        swell(at - vec2(step_m, 0.0)) - swell(at + vec2(step_m, 0.0)),
        2.0 / ripple_steepness,
        swell(at - vec2(0.0, step_m)) - swell(at + vec2(0.0, step_m))
    ));
    NORMAL = normalize((VIEW_MATRIX * vec4(slope, 0.0)).xyz);

    // Edge-on, water is a mirror of the sky; looked down into, it is its own colour. That is
    // Fresnel, and without it a sea is a sheet of flat blue whatever angle it is seen from.
    float facing = clamp(dot(normalize(-VERTEX), NORMAL), 0.0, 1.0);
    float glancing = pow(1.0 - facing, 4.0);

    ALBEDO = mix(mix(shallow_colour, deep_colour, depth), sky_tint, glancing);
    // Clear at the shoreline, closing up as it deepens, and closing up again where the surface
    // is edge-on: the ground has to come up through it rather than stop at a line, and the
    // horizon has to be sea rather than a window onto the sky.
    ALPHA = clamp(mix(1.0 - edge_clarity, body_opacity, depth) + glancing, 0.0, 1.0);
    ROUGHNESS = 0.12;
    METALLIC = 0.0;
    SPECULAR = 0.5;
}
