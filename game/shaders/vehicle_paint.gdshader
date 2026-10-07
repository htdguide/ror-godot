shader_type spatial;
// **No `ALPHA` is written anywhere in this shader and that is deliberate.** Writing it at all puts
// the surface in Godot's transparent pass, where it loses the depth prepass and is sorted per
// object rather than per pixel — measured on the hero truck, the painted panels stopped covering
// what is behind them and the vehicle's share of the frame fell from 53% to 42%. Paint is opaque.
// A pane of glass is not, and glass keeps the built-in material.
render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

// Automotive paint: a pigmented base layer under a clear coat, plus a sheen lobe for cloth.
//
// **Why this is not `StandardMaterial3D.clearcoat`.** Godot has the property and it does not
// layer — it trades the base away for the highlight. Measured on one sphere under one sun, at a
// fixed exposure, with nothing changing but the coat (`harness/dev/paint_probe.gd`):
//
//     clearcoat 0.00   centre 0.2096
//     clearcoat 0.25   centre 0.1849   (0.88x)
//     clearcoat 1.00   centre 0.0688   (0.33x)
//
// A clear coat is a dielectric film at IOR 1.5. It reflects 4% of what arrives head-on, so the
// paint under it should lose 4% and not 67%. That darkening is what `material_cfg.gd` records as
// panels reading "half transparent", and why the project's car paint sits at a coat of 0.25 — a
// number chosen to hide an artefact rather than to describe a surface.
//
// The composition here is glTF's `KHR_materials_clearcoat`: the coat's own GGX lobe is added, and
// what passes through it is attenuated by the coat's Fresnel term at the viewing angle —
//
//     f_clearcoat = clearcoat * F_schlick(0.04, NdotV)
//     colour      = base * (1 - f_clearcoat) + clearcoat_brdf
//
// so at normal incidence the base keeps 96% of itself whatever the coat is set to, and the coat's
// reflection takes over only as the surface turns edge-on. That is the effect a car body has: dark
// paint straight on, white sky sliding along the shoulder line.
//
// **The coat's reflection of the sky is the engine's, and getting it needs one trick.** Godot
// computes image-based lighting at one roughness per pixel and a coated surface has two: the paint
// at 0.45 and the film over it at 0.06. The sharp one is the one that matters — a car body reads as
// a car body because the sky slides along its shoulder line — so `ROUGHNESS` is handed to the
// engine as the coat's, and the paint's own roughness travels to `light()` in `BACKLIGHT`, which
// Godot reads only in the lighting code this shader replaces.
//
// Without that the coat is a pure loss. It takes the Fresnel share away from the paint and the
// only thing it gives back is a direct specular lobe a fraction of a pixel wide — measured, a coat
// of 1.0 took the ball's silhouette from 0.4081 to 0.4044 and put nothing in its place, which is a
// worse picture than no coat at all. What is still missing is the paint's own broad sky sheen,
// which is a 4% term under a sharp one, and the second radiance lookup that would restore it is
// not something a shader can ask Godot for.

// What the surface is made of. Albedo is the mod's own texture where it supplies one — the legacy
// format carries a diffuse map and nothing else — and the rest comes from the material class.
uniform vec4 albedo : source_color = vec4(0.7, 0.7, 0.72, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform bool albedo_textured = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
// A legacy specular map, already inverted into roughness on the way in. See
// `MaterialClass.roughness_from_specular`.
uniform sampler2D roughness_texture : filter_linear_mipmap, hint_default_white;
uniform bool roughness_textured = false;

// The coat. `clearcoat` is how much of the surface is coated, which for paint is all of it;
// `clearcoat_roughness` is how polished that coat is.
uniform float clearcoat : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.06;

// Cloth and leather: a wide, pale lobe at grazing angles that no metallic-roughness parameter can
// produce. Godot has no sheen of its own — `StandardMaterial3D` has no such property in 4.7 —
// which is why `MaterialCfg` has stated a sheen for seats and tyres that nothing ever read.
uniform float sheen : hint_range(0.0, 1.0) = 0.0;
uniform float sheen_roughness : hint_range(0.05, 1.0) = 0.3;
uniform vec3 sheen_colour : source_color = vec3(1.0, 1.0, 1.0);

// How strong the base layer's own highlight is, as Godot's `specular` means it: 0.5 is the 4%
// every dielectric reflects, and 0 is a pass whose author wrote a black specular colour.
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float emission_energy = 0.0;

// A dielectric's reflectance at normal incidence, for IOR 1.5: ((1 - 1.5) / (1 + 1.5))^2. The
// same number for the clear coat and for the base layer, because both are the same kind of
// surface — only a metal differs, and a metal reflects its own albedo.
const float DIELECTRIC_F0 = 0.04;
const float MIN_ALPHA = 0.0001;


float f_schlick(float f0, float cosine) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cosine, 0.0, 1.0), 5.0);
}


// Trowbridge-Reitz / GGX, as Walter et al. 2007 states it. `alpha` is roughness squared.
float d_ggx(float n_dot_h, float alpha) {
    float a2 = alpha * alpha;
    float d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, MIN_ALPHA);
}


// Smith's masking-shadowing term, height-correlated (Heitz 2014), already divided by the
// 4 * NdotL * NdotV of the microfacet denominator.
float v_smith_ggx(float n_dot_l, float n_dot_v, float alpha) {
    float a2 = alpha * alpha;
    float lv = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
    float ll = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
    return 0.5 / max(lv + ll, MIN_ALPHA);
}


// The Charlie distribution, Estevez & Kulla 2017: the cloth lobe, which peaks at the silhouette
// rather than at the mirror direction.
float d_charlie(float n_dot_h, float sheen_alpha) {
    float inverse = 1.0 / max(sheen_alpha, 0.05);
    float sin2 = max(1.0 - n_dot_h * n_dot_h, 0.0);
    return (2.0 + inverse) * pow(sin2, inverse * 0.5) / (2.0 * PI);
}


// Neubelt & Pettineo 2013's visibility term for that lobe, which is what the Charlie
// distribution is published with.
float v_neubelt(float n_dot_l, float n_dot_v) {
    return 1.0 / max(4.0 * (n_dot_l + n_dot_v - n_dot_l * n_dot_v), MIN_ALPHA);
}


void fragment() {
    vec4 colour = albedo;
    if (albedo_textured) {
        colour *= texture(albedo_texture, UV);
    }
    ALBEDO = colour.rgb;
    METALLIC = metallic;
    // **What the engine reflects the sky off is the coat, in the share the coat actually
    // reflects.** A coated surface has two roughnesses and Godot's image-based lighting takes one,
    // so this picks between them by Fresnel: a film at IOR 1.5 sends back 4% of what arrives
    // head-on and nearly all of it at a glancing angle, so a panel seen face-on reflects the sky
    // the way its paint does — broadly, dully — and turns into the coat's mirror only as it turns
    // away.
    //
    // Handing the engine the coat's roughness outright was the first attempt, and it makes every
    // panel a 0.06-roughness mirror of the sky at every angle. Reported from a window at 6.1 h: the
    // truck's bed shining at dawn. The sky at that hour is almost as bright as noon's while the
    // ground is eighteen times darker — which is what dawn is — so a body that mirrors it reads as
    // lit from nowhere.
    float paint_roughness = roughness_textured
        ? texture(roughness_texture, UV).r
        : roughness;
    float facing = max(dot(NORMAL, VIEW), 0.0001);
    float coat_share = clearcoat * f_schlick(DIELECTRIC_F0, facing);
    ROUGHNESS = mix(paint_roughness, clearcoat_roughness, coat_share);
    BACKLIGHT = vec3(paint_roughness);
    SPECULAR = specular_amount;
    if (emission_energy > 0.0) {
        EMISSION = ALBEDO * emission_energy;
    }
}


// Direct light, for every light in the scene. The image-based part stays Godot's, reflecting off
// the coat at the roughness `fragment()` handed it.
void light() {
    // `max` rather than an early exit: a `return` in `light()` does not compile — "Using 'return'
    // in the 'light' processor function is incorrect" — and a surface facing away from the light
    // then has to add nothing instead of being skipped.
    float n_dot_l = max(dot(NORMAL, LIGHT), 0.0);
    vec3 half_vector = normalize(VIEW + LIGHT);
    float n_dot_v = max(dot(NORMAL, VIEW), MIN_ALPHA);
    float n_dot_h = max(dot(NORMAL, half_vector), 0.0);
    float v_dot_h = max(dot(VIEW, half_vector), 0.0);
    vec3 arriving = LIGHT_COLOR * ATTENUATION * n_dot_l;

    // **The coat, and what is left for everything under it.** One Fresnel term at the viewing
    // angle does both jobs, which is what makes the layering add up: whatever the coat reflects
    // is exactly what the base does not receive.
    float coat_fresnel = clearcoat * f_schlick(DIELECTRIC_F0, n_dot_v);
    float under_coat = 1.0 - coat_fresnel;
    float coat_alpha = max(clearcoat_roughness * clearcoat_roughness, MIN_ALPHA);
    float coat_lobe = clearcoat
        * f_schlick(DIELECTRIC_F0, v_dot_h)
        * d_ggx(n_dot_h, coat_alpha)
        * v_smith_ggx(n_dot_l, n_dot_v, coat_alpha);

    // The base layer, metallic-roughness as the glTF specification states it: a metal has no
    // diffuse and reflects its own colour, a dielectric reflects 4% white and keeps its pigment.
    // The paint's own roughness, which `fragment()` put here because `ROUGHNESS` belongs to the
    // coat. The red channel, because that is the channel `roughness_from_specular` writes.
    float paint_roughness = BACKLIGHT.r;
    float base_alpha = max(paint_roughness * paint_roughness, MIN_ALPHA);
    // Godot's own relation between the `specular` property and a dielectric's reflectance:
    // `0.16 * specular^2`, which is 0.04 at the default of 0.5.
    float stated_f0 = 0.16 * specular_amount * specular_amount;
    vec3 f0 = mix(vec3(stated_f0), ALBEDO, METALLIC);
    vec3 base_fresnel = f0 + (1.0 - f0) * pow(clamp(1.0 - v_dot_h, 0.0, 1.0), 5.0);
    vec3 base_specular = base_fresnel
        * d_ggx(n_dot_h, base_alpha)
        * v_smith_ggx(n_dot_l, n_dot_v, base_alpha);
    // **No `ALBEDO` in here.** Godot multiplies whatever `light()` adds to `DIFFUSE_LIGHT` by the
    // albedo itself, so a shader that applies it as well applies it twice — measured against the
    // built-in material on the same patch under the same sun, a mid-grey surface came back at
    // 0.1696 where the engine's own read 0.7602, and the ratio tracked the albedo rather than
    // being a constant. A metal has no diffuse at all.
    float base_diffuse = (1.0 - METALLIC) * (1.0 / PI);

    vec3 cloth = sheen_colour * sheen
        * d_charlie(n_dot_h, sheen_roughness)
        * v_neubelt(n_dot_l, n_dot_v);

    DIFFUSE_LIGHT += arriving * base_diffuse * under_coat;
    SPECULAR_LIGHT += arriving * (base_specular * under_coat + vec3(coat_lobe) + cloth);
}
