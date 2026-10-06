shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// A terrain's sea: a flat plane at the height its own `.terrn2` states, made to read as water.
//
// Flat on purpose. A terrain declares `Water` and `WaterLine` and nothing more, so a height is all
// the file gives and a wave height is something this project would be inventing. What the shader
// does is make a plane at one height read as water rather than as a sheet of coloured glass. Four
// things do that, and they are all measurements rather than tints:
//
//   refraction     what is under the water is sampled through a bent surface, so a post standing
//                  in it breaks at the waterline
//   extinction     Beer-Lambert. Water absorbs red first, so depth turns the sea bed green and
//                  then blue and then nothing, which is why the deep is a colour nobody painted
//   reflection     the engine's own image-based lighting, off a dielectric at IOR 1.33. A real
//                  image of this hour's sky rather than a stated blue
//   slope          the surface has a normal that varies, so the sun lands on it as a glitter path
//                  instead of as one egg
//
// **The reflection is not hand-rolled and the Fresnel is not either.** A previous version mixed in
// a `sky_tint` uniform by `pow(1 - facing, 4)`, which is a painting of the effect: the sea was a
// pale sheet, slightly lighter than the sky it was supposed to be reflecting, at every hour and
// every weather. Water is a dielectric, the engine already reflects the sky off dielectrics, and
// the only thing it needs to be told is the roughness.
//
// **Transparent, and `ALPHA` is written as 1.0 on purpose.** Writing `ALPHA` at all is what puts a
// surface in the transparent pass, which this one needs: the screen texture it refracts through is
// resolved from the opaque pass, so there has to be an opaque pass that has already finished. What
// comes out is opaque, because the water's own blending is done here where the depth of it is
// known — see `hard-won-facts-materials.md` for what writing `ALPHA` costs a surface that is not
// water.

// **Neither of these may be mipmapped.** A screen texture sampled with `filter_linear_mipmap` picks
// its mip from the screen-space derivatives, and on a surface seen at a grazing angle those are
// enormous: the sea sampled the smallest mip, which is the average of the whole frame, and painted
// itself one flat grey at every angle and every depth. Sampling the frame you are drawing into is
// a lookup, not a texture on a surface.
uniform sampler2D depth_buffer : hint_depth_texture, filter_linear;
uniform sampler2D behind : hint_screen_texture, filter_linear;

// **Beer-Lambert, per metre, per channel, and red is the big one.** Pure water absorbs roughly
// 0.35 per metre at 650 nm, 0.06 at 550 and 0.01 at 440: red is gone in the first few metres and
// blue survives tens of them. These are those, raised for the silt a harbour has in it. Written in
// RGB order, which is the trap — the published figures are listed by wavelength, shortest first,
// and entering them in that order put the largest coefficient on blue. Measured as a bright orange
// band along every shoreline, because shallow water was absorbing everything except red.
uniform vec3 extinction = vec3(0.45, 0.10, 0.045);
// What the water scatters back towards the eye once nothing is left of the bed. This is the only
// stated colour in the shader and it is the one real water has: light that never reached the
// bottom at all.
uniform vec3 scattered : source_color = vec3(0.045, 0.12, 0.145);
// How far the surface bends what is under it, in metres at one metre of depth. Shallow water
// bends little because there is little of it in the way.
uniform float refraction_m : hint_range(0.0, 2.0) = 0.45;
// How big the ripples are across the surface, in metres, and how steep.
uniform float ripple_m : hint_range(0.2, 40.0) = 1.8;
uniform float ripple_steepness : hint_range(0.0, 1.0) = 0.55;
// How fast the surface moves, and the clock it moves on. Negative takes the wall clock, which is
// what a window wants; a measurement sets a number, because a frame that animates with wall-clock
// time is a different frame every time it is taken. Same convention as `foliage.gdshader`.
uniform float ripple_speed : hint_range(0.0, 2.0) = 0.22;
uniform float wave_phase = -1.0;
// **Not a mirror.** A sea polished to nothing reflects the sun as a single sub-pixel point and the
// glitter path disappears — the same sub-pixel lobe that makes a clear coat's own highlight
// invisible, recorded in `hard-won-facts-materials.md`. Real water is this rough.
uniform float surface_roughness : hint_range(0.0, 0.4) = 0.055;
// How opaque the water is. A uniform rather than a literal 1.0, because a constant there is
// something the shader compiler can fold away, and what it folds away with it is the surface's
// place in the transparent pass — which is where the screen texture it refracts through exists.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

const float MIN_DEPTH_M = 0.001;
// Water's reflectance looking straight down into it, from its own index of refraction:
// ((1 - 1.33) / (1 + 1.33))^2. Fresnel takes it from there to 1.0 at the horizon.
const float WATER_F0 = 0.0203;
// How far the refracted sample is allowed to reach, in metres of screen offset. A bend that runs
// off the edge of what the opaque pass drew samples the sky and puts a patch of it under the
// water.
const float MAX_BEND = 0.06;
// How far away the surface is flat, in metres. **Not a performance trick — an anti-alias.** A
// ripple a metre across is a fraction of a pixel at two hundred metres, and a normal that changes
// faster than the pixels can carry it reads as a crawling band of noise along the horizon rather
// than as water. Distance flattens it towards a mirror, which is also what distance does to real
// water: past a few hundred metres the sea is a reflection of the sky and nothing else.
const float FLAT_BY_M = 30.0;


// The surface, as a height field in metres.
//
// **Six waves whose frequencies share no common multiple**, so the pattern does not come back.
// Three did, and at a ripple scale of a few metres the repeat was visible across any open water as
// a regular quilt — reported from a window in those words. The ratios here are irrational on
// purpose: a sum of sines repeats on the lowest common multiple of its periods, and there is not
// one.
float swell(vec2 at, float clock) {
    float h = sin(at.x * 1.000 + at.y * 0.350 + clock * 1.00);
    h += 0.70 * sin(at.x * -0.451 + at.y * 1.103 + clock * 1.31 + 1.7);
    h += 0.45 * sin(at.x * 0.803 + at.y * -0.947 + clock * 0.79 + 3.1);
    h += 0.31 * sin(at.x * 1.732 + at.y * 1.414 + clock * 1.73 + 5.2);
    h += 0.22 * sin(at.x * -2.236 + at.y * 0.618 + clock * 2.24 + 0.8);
    h += 0.14 * sin(at.x * 0.382 + at.y * -2.645 + clock * 2.65 + 4.4);
    return h * 0.28;
}


// How far, in metres, a point on the screen is behind the water's surface.
float water_between(vec2 screen_uv, mat4 inverse_projection, float surface_view_z) {
    float raw = textureLod(depth_buffer, screen_uv, 0.0).r;
    // **The depth value is already NDC z.** Remapping it with `* 2.0 - 1.0`, as an OpenGL-era
    // snippet does, puts the sea bed at the wrong distance and everything reads as shallow — the
    // whole sea then draws at its shoreline colour and the bottom shows through all of it.
    vec4 view = inverse_projection * vec4(screen_uv * 2.0 - 1.0, raw, 1.0);
    view.xyz /= view.w;
    return max(0.0, -view.z - surface_view_z);
}


void fragment() {
    vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float clock = wave_phase < 0.0 ? TIME : wave_phase;
    vec2 at = world.xz / ripple_m;
    float moment = clock * ripple_speed;

    // The slope of the water, differenced rather than stored: a normal map without a texture.
    float step_m = 0.35;
    float detail = 1.0 / (1.0 + length(VERTEX) / FLAT_BY_M);
    vec3 slope = normalize(vec3(
        (swell(at - vec2(step_m, 0.0), moment) - swell(at + vec2(step_m, 0.0), moment)) * detail,
        2.0 / ripple_steepness,
        (swell(at - vec2(0.0, step_m), moment) - swell(at + vec2(0.0, step_m), moment)) * detail
    ));
    NORMAL = normalize((VIEW_MATRIX * vec4(slope, 0.0)).xyz);

    float surface_view_z = -VERTEX.z;
    float straight_through = water_between(SCREEN_UV, INV_PROJECTION_MATRIX, surface_view_z);

    // **What is under the water, seen through it.** The surface's own slope displaces the sample,
    // which is refraction as far as a single flat plane can carry it: the direction is the
    // surface normal and the distance is how much water the ray has to cross.
    vec2 bend = NORMAL.xy * refraction_m * clamp(straight_through, 0.0, 4.0) * 0.01;
    bend = clamp(bend, vec2(-MAX_BEND), vec2(MAX_BEND));
    vec2 bent_uv = clamp(SCREEN_UV + bend, vec2(0.001), vec2(0.999));
    float through = water_between(bent_uv, INV_PROJECTION_MATRIX, surface_view_z);
    // A bent sample that landed on something in front of the water is something standing out of
    // the sea — a post, a hull, the far shore — and bending it would smear that thing sideways
    // into the water in front of it. Those pixels are taken straight.
    if (through <= MIN_DEPTH_M) {
        bent_uv = SCREEN_UV;
        through = straight_through;
    }

    // Beer-Lambert on the way down and on the way back up, so the path is twice the depth, and
    // what the water scatters back fills in exactly what the absorption took.
    vec3 survives = exp(-extinction * through * 2.0);

    // **In `ALBEDO`, which is an approximation, and the honest alternative does not exist.** What
    // comes up through the water is light that was lit and exposed already, in the pass this is
    // reading back, so it belongs in `EMISSION` — and `EMISSION` is in physical light units. At a
    // daylight exposure that normalisation is of the order of a thirty-thousandth, so an emission
    // of 1.0 renders black: measured, a sea told to emit pure green came back with no green in it
    // at all. Godot gives neither a shader nor a script that number —
    // `CameraAttributesPhysical` has no method for it — so there is nothing to divide by. Here the
    // refracted view is modulated by the light falling on the surface, which outdoors is the same
    // sky that lit the sea bed a moment earlier, and wrong in shadow: a shadow across the water
    // darkens what is under the water with it.
    ALBEDO = textureLod(behind, bent_uv, 0.0).rgb * survives + scattered * (1.0 - survives);

    // **A dielectric, and its reflection is the engine's.** Water is IOR 1.33, so it reflects 2%
    // of what is above it looked straight down into and nearly all of it at the horizon, and
    // Godot's image-based lighting reflects a real picture of this hour's sky rather than a stated
    // blue.
    //
    // **It falls short at the horizon and that is measured, not suspected.** On a level view over
    // open water the sea just under the horizon reads 0.296 of the sky just over it; a mirror put
    // in the same frame reads 0.93, so the radiance map holds the sky and it is the dielectric
    // response that does not reach 1.0 at grazing. Computing the Fresnel share here from the
    // published index and handing it to the engine as `METALLIC` was tried — the ramp measures
    // correctly, 0.05 looking down and 0.9 at the horizon — and the sea came out a flat milky
    // sheet with its waves washed out of it. So the horizon is too dark, it is written down, and
    // the fix waits on knowing why rather than on a second guess stacked on the first.
    METALLIC = 0.0;
    ROUGHNESS = surface_roughness;
    SPECULAR = 0.5;

    // **Written, and that is the point of writing it.** `ALPHA` is what puts this surface in the
    // transparent pass, and the transparent pass is where the screen texture it refracts through
    // and the depth of what is under it both exist. Without it the sea came back opaque: the depth
    // behind it measured zero everywhere, the screen it sampled was black, and it drew as a sheet
    // of its own scattering colour with no bed, no shoreline and no plate under it. A uniform
    // rather than a literal, because a constant is something the compiler can fold away and take
    // the transparent pass with it.
    ALPHA = opacity;
}
