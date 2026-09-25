# Rigs of Rods → Godot 4.x: Rendering Rewrite Plan

## Context

Rigs of Rods renders on OGRE 1.x. That renderer is the bottleneck on how the game looks, not the
simulation: no PBR, no HDR pipeline or tonemapper, no GI or AO, weak PSSM shadows, no modern AA or
upscaler, no SSR, sprite particles, 2010-era terrain and vegetation, and single-threaded draw
submission that is draw-call-bound long before the GPU is busy. The softbody solver is the part of
RoR that is actually good and is not the problem.

So: keep the simulation, replace the renderer. Godot 4.x becomes the shell — windowing, scene graph,
renderer, asset loading, UI — and RoR's node/beam solver comes along as a C++ GDExtension. Godot's
physics engine is not used for vehicle simulation at all.

Development is CLI-only through the ClaudeGodot editor, with no human eyes in the loop by default.
That constraint drives two structural decisions that come before any rendering work: everything
tunable lives in `.gd` / `.gdshader` (never in a `.tscn`), and a screenshot/metrics harness is
commit #1 so the agent can see what it is doing.

### Decisions already fixed (from grilling, 2026-09-25)

| Question | Decision |
| --- | --- |
| Solver integration | C++ GDExtension wrapping the existing RoR beam solver. No reimplementation. |
| Engine fork | Stock Godot first. Fork only where proven impossible, patch set kept minimal and listed. |
| Legacy content | Runtime compatibility shim: existing `.truck` / `.zip` / OGRE assets load unmodified. |
| Target | Tech demo first: one hero vehicle, one terrain. No multiplayer/UI/game-mode work. |
| Platform | **macOS only for now.** The dev Mac is the sole authority for pixels, timings, and logic gates. No Linux/`xvfb`/lavapipe lane — deferred for speed, kept cheap to add later via the portability rules in §3.5. |
| Hero asset | An existing community truck with its original diffuse-only textures, unchanged. |
| Frame budget | 1080p, 60 fps, one truck + terrain. |
| Showcase scene | One beautiful drivable scene ("Valley One") built from free third-party assets, standing up from M1 and dressed progressively by every later milestone. Spec in §0.5. |
| Terrain layer | **Terrain3D** (TokisanGames, MIT, asset-library #3892) instead of writing our own clipmap. Rationale and integration in §0.6. |
| Camera and post | Physical camera model (`CameraAttributesPhysical`: focal length, f-stop, shutter) plus a full post stack — AO, DOF, motion blur, glow, grade, grain, flare. Its own milestone, M2b. |

Two of those answers pull against each other and the plan resolves them explicitly:

- *Runtime shim* is a large permanent surface; *tech demo* wants one truck. Resolution: the shim is
  built as a **read-only legacy loader** with a first-load conversion cache. Demo-blocking parts
  (`.truck`, OGRE `.mesh`, textures, one terrain) land in M1. Breadth across the mod archive becomes
  a corpus gate that only asserts "loads, or fails cleanly with a named reason" — not fidelity.
- *Unchanged diffuse-only hero textures* means milestone (a) cannot be judged on texture quality.
  Its acceptance criteria are therefore about **lighting correctness** measured against third-party
  reference renders, not about the truck looking good. Re-texturing the hero asset is scheduled as
  its own visible-payoff milestone after TAA lands.

---

## 0. Ground rules that apply to every milestone

**Scene purity.** `.tscn` files contain structure only: node hierarchy, names, and references to
scripts/resources. No numeric tunables, no material parameters, no camera values, no environment
settings. Every world is assembled by a builder function in `.gd`
(`res://world/world_builder.gd::build(cfg) -> Node3D`), and every tunable lives in a const dictionary
under `res://config/` (`render_cfg.gd`, `light_cfg.gd`, `material_cfg.gd`, `camera_cfg.gd`). A gate
`scene_purity` fails the build if any `.tscn` contains a property assignment outside an allowlist of
structural keys. This makes hand-edit drift a build failure instead of an invisible source of
"why does it look different on my machine".

**Goldens are never self-approved.** A gate may not write its own expected value. Every golden PNG is
captured under an explicit `--update-golden` flag, lands with a manifest recording engine version,
rendering driver string, GPU name, git SHA, seed, and convergence frame count, and requires a human
approval line in the manifest. Where an outside oracle exists, the gate compares against *that*, not
against a previously captured frame — see the oracle list in §3.4.

**Determinism before beauty.** No gate may depend on wall-clock timing, frame-rate-dependent
integration, or unseeded randomness. `--deterministic` forces the solver to a single thread and a
fixed substep count per frame so that a golden image is reproducible on the same machine.

**The human is in the loop, and a milestone does not close without them.** Automated gates catch
regressions; they do not tell you whether the game looks good or drives right. So every milestone that
has anything human-testable ends with an **interactive session**: the agent launches a real window on the
dev Mac, hands over the controls, and the user drives, flies the camera, toggles effects, and gives a
verdict. Rules:

1. The agent may not mark a human-gated milestone complete. Only the user closes it — automated gates
   green is a precondition for asking, not a substitute for the answer.
2. The session is launched by one command (`tools/play.sh`, §3.6), never by hand-assembling arguments.
3. Anything the user reports in a session becomes either a new automated gate or a named
   deferred item before the milestone closes. Verbal findings that vanish are the failure mode here.
4. A session where the user found nothing still counts as a pass and is recorded as one.

**Third-party assets and addons: use them freely, but ask first.** The Godot asset library and the
CC0/CC-BY asset world are the right place to get terrain systems, vegetation, HDRIs, materials, props,
and tools — writing them ourselves is wasted work. The rule is procedural, not restrictive:

1. Nothing third-party is adopted without explicit user approval, asked *before* adding it.
2. The ask names: what it is, author, licence, version, why it beats writing it ourselves, and what it
   would cost to drop later.
3. Once approved it is recorded in `THIRD_PARTY.md` with source URL, version/commit pin, licence,
   attribution string, and the reason for adoption.
4. Licences are gated, not trusted: the `asset_licenses` gate fails the build if any asset or addon file
   lacks a `LICENSES/` record. Engine-locked assets (Unreal/Megascans marketplace content) are rejected
   by name — that restriction survives format conversion and is the easiest way to poison the project.
5. Every third-party version is pinned. No floating dependencies, because a silent addon update that
   changes a shader also changes every golden image.

Already-approved: **Terrain3D** (asset library #3892, MIT, TokisanGames) per §0.6. Everything else in
the asset shortlists below is a *candidate* and needs its own ask.

---

## 0.5 The showcase scene — "Valley One"

The first scene is a deliverable, not a test fixture. Every milestone is judged inside it, and it must
look good on its own terms while also being genuinely drivable so the softbody solver is doing real
work in every shot. One scene, dressed progressively — never a second "pretty but empty" demo level.

### What it has to contain

Chosen so that each of the graphics milestones has something in frame to show off:

- **Real topography, drivable.** A valley roughly 2 × 2 km: a climbing dirt road with switchbacks,
  a rocky off-camber traverse, a river crossing with a ford, a washed-out section with ruts and
  boulders, and one long straight for speed shots. Slopes and obstacle scale are tuned to what RoR's
  solver actually likes — this is a physics playground first, a diorama second.
- **Water.** A river through the valley floor and a lake at the low end: shoreline, shallow ford,
  depth gradient. Gives reflections, refraction, wetness, spray, and later buoyancy something real.
- **Hard shadow subjects.** A conifer stand for dappled light and god rays, a rock face for long raking
  shadows, a short tunnel or overhang for GI and headlight work, and a bridge for silhouette shots.
- **Atmosphere volume.** Valley floor mist, altitude haze, and a fog bank at the lake end, so
  volumetric lighting has geometry to slice.
- **Sky variety.** The same geometry readable at dawn, noon, overcast, dusk, night, and rain.
- **Vegetation.** Grass, shrubs, trees at three density tiers, because 2010-era vegetation is one of
  the most obvious tells in the current renderer.

### Where the assets come from, and the licence trap

**Decision: assemble Valley One from free, clearly-licensed third-party assets over a public-domain
real-world heightmap, rather than adopting a single ready-made map.** Reasons, in order:

- Almost every high-fidelity ready-made map is unusable here. Epic's free Megascans/Quixel and
  marketplace environments are licensed **for use in Unreal Engine only** — they cannot ship in a Godot
  project, and that restriction survives conversion. BeamNG, Assetto Corsa, and similar maps are
  proprietary. This is the trap to avoid before anyone starts converting anything.
- The RoR archive's own terrains load through our shim on day one, which is useful for *testing*, but
  they are exactly the 2010-era look the rewrite exists to escape (see R10). One legacy terrain stays
  in the gate set as a compatibility subject; it is not the showcase.
- A real-world DEM gives topography that reads as plausible for free, which is the single hardest thing
  to fake by hand, and public-domain elevation data carries no licence risk.

Sourcing tiers, in preference order (each one still needs the §0 approval ask before adoption):
1. **Godot asset library, MIT/CC0** — first place to look, for both tools and content. Terrain3D came
   from there and is already approved; its own demo terrain is the day-one blockout. Other candidates to
   ask about as the milestones need them: vegetation/foliage kits, sky and cloud addons, water addons
   (as a reference to read, not to ship, since our water must feed the solver), and post-processing
   effect collections.
2. **CC0 libraries** — heightmap from public-domain elevation data (USGS 3DEP is public domain;
   Copernicus DEM is free with attribution); PBR ground/rock/bark materials and HDRIs from Poly Haven
   and ambientCG; CC0 vegetation and prop kits.
3. **CC-BY** — higher-end environment sets from open-movie/production sources are CC-BY and acceptable
   with attribution; a forest or canyon set from one of these can supply hero vegetation and rock
   assets wholesale.
4. **A ready-made CC0/CC-BY/MIT map, if a good one turns up** — the scene builder is written
   asset-agnostic precisely so a found map can be dropped in and take over. Requirements for adoption:
   a heightmap or heightmap-derivable terrain, a licence file naming licence and author, and no
   engine-locked dependencies.

**Licence hygiene is a gate, not a promise.** Every asset lands with a `LICENSES/<asset>.md` recording
source URL, author, licence, and any attribution string. A `asset_licenses` gate fails the build if any
file under the scene's asset directories has no licence record. Anything Unreal-locked is rejected at
that gate by name.

### Structure, given the CLI-only rule

The scene is built by `res://world/valley_one.gd` from a declarative layout in
`res://world/valley_one_layout.gd`: terrain source, road spline control points, prop placements,
vegetation density maps, water bodies, and named camera anchors. No `.tscn` for the scene, no hand
placement in an editor — which also means the scene is diffable and reviewable as text.

Weather and time of day are **presets**, each a const dictionary in `res://config/weather_cfg.gd`
combining sun angle and colour, sky, fog and volumetric settings, cloud/HDRI choice, wetness level, and
particle activity: `dawn_mist`, `noon_clear`, `overcast`, `golden_dusk`, `night_clear`,
`rain_storm`, `fog_bank`. A preset name is a CLI argument, so any gate can be run under any weather.

### The money shots

A fixed set of eight frames that every visual milestone re-renders, so progress is legible as one
before/after sheet across the whole project:

1. `valley_vista` — dawn mist over the valley from the ridge, sun low and behind the conifer stand.
2. `switchback_backlit` — truck climbing, low sun through trees, god rays and long shadows.
3. `ford_crossing` — truck in the river, spray and wet bodywork, water reflections.
4. `tunnel_headlights` — night, headlights on, volumetric shafts, GI in an enclosed space.
5. `rock_traverse` — off-camber articulation close-up, hard shadow on the suspension geometry.
6. `lake_dusk` — still water, golden dusk, reflected sky and rock face.
7. `rain_road` — rain, wet asphalt-ish road surface, headlight reflections, spray from the wheels.
8. `wheel_macro_mud` — tyre in a rut, mud, contact shadow, grime on the bodywork.

Each money shot names which milestones it is diagnostic for, and the `--all` gate run always emits the
eight-shot sheet at the end so the current state of the project is one image.

### Staging: the scene is never blocked on a late milestone

The scene stands up in M1 and improves. Notably, water and weather do **not** wait for M8:

- **M1** — terrain, road, collision, blockout props, flat placeholder water, legacy-equivalent
  materials. Ugly, drivable, complete in layout.
- **M2** — PBR ground and rock materials, HDRI sky per weather preset, vegetation tier 1, simple
  reflective/refractive water plane with depth fade and a shoreline term, fog. This is the milestone
  where the scene first looks good.
- **M4/M5** — GI, shadow overhaul, night and dusk presets, volumetric shafts, tunnel.
- **M6** — SSR on the water and the road, rain wetness, terrain decals (puddles, ruts, tyre marks).
- **M7** — dust, spray, tyre smoke, rain particles; vegetation tiers 2 and 3.
- **M8** — FFT water replaces the M2 plane on the lake; terrain texel density raised.

**Decision: staged water rather than waiting for the FFT implementation.** A reflective, refractive,
depth-faded water plane with a scrolling normal map is a few hundred lines of `.gdshader` and gives the
ford and the lake immediately; the FFT solver at M8 replaces the surface generation behind the same
material interface and the same water-height query, so nothing downstream is rewritten. Rejected:
pulling M8 forward to get water — it would delay the milestones with far better payoff per unit work.

### A consequence to state plainly

A beautiful environment beside an untouched diffuse-only truck will make the truck the ugliest thing in
frame. That contrast is the strongest argument for moving the hero-asset re-texture up, and it is
scheduled immediately after M3 for that reason (see R10). Until then, the money shots deliberately
favour framings where the environment carries the image.

---

## 0.6 Terrain3D as the terrain layer

Asset-library entry #3892 is **Terrain3D** by TokisanGames: a C++ GDExtension clipmap terrain system,
MIT-licensed, Godot 4.4–4.6, macOS included. It is not a demo map — it is the terrain engine, which is
considerably more useful. **Decision: adopt it, and delete our own terrain work.**

What it removes from this plan:
- The hand-written GPU clipmap mesh, LOD ring logic, and heightmap sampling that M8 had scheduled.
- The splat-texture-array scheme, which it already provides (up to 32 textures, 10 LOD levels).
- The vegetation scattering system, via `Terrain3DInstancer`.

Why it beats writing our own: it is the same architecture we had chosen anyway (clipmap + splat array,
not virtual texturing), it is C++ so it does not spend GDScript time per frame, it is MIT so there is
no licence entanglement, and it is maintained by people whose whole job is terrain. Writing it ourselves
buys nothing except bugs.

**It also fits the CLI-only constraint, which was the thing to verify before adopting it.** Verified:

- Terrain is built from code, not the editor GUI: `Terrain3DData.import_images(images, global_position,
  offset, scale)` takes height/control/colour `Image`s. So a DEM heightmap is imported by a
  `--headless --script` tool, and the terrain becomes a generated artifact, not a hand-edited binary.
- **Collision mode is set to `Disabled`.** RoR's own collision system stays authoritative; Godot physics
  never touches the terrain. Terrain3D's docs agree that physics-based collision is neither the only nor
  the fastest route.
- Height and normal queries are available without physics: `Terrain3DData.get_height(global_position)`,
  `get_normal(global_position)`, `get_mesh_vertex(lod, filter, global_position)`, plus direct region
  image access for bulk lookups. This is exactly the interface RoR's collision and buoyancy code needs,
  and it is what the bridge exposes to the solver.
- The terrain material accepts a custom shader override, so our PBR, wetness, grime, decal-response,
  and texel-density work is authored as one `.gdshader` against Terrain3D's shader rather than as a
  separate terrain renderer.

The integration seams, all owned by us:
1. `tools/import_dem.gd` — DEM → height/control/colour images → `import_images()`, plus road-spline
   carving and ruts written into the heightmap at import time so the drivable surface is data, not
   geometry authored by hand.
2. `res://compat/terrain3d_collision_bridge.gd` + its C++ counterpart — wraps `get_height` /
   `get_normal` / raw region access behind the height-query interface RoR's collision expects. Bulk
   region access, not per-wheel scalar calls, because a softbody with many contact points will hammer
   this every substep.
3. `res://shaders/terrain3d_override.gdshader` — our shader override, version-pinned against the
   Terrain3D release and tracked like a patch, since an upstream shader change moves every golden image.
4. Legacy RoR terrains keep loading through the shim on their own path (§4.5); they do not go through
   Terrain3D. Two terrain paths is the honest cost of both showcasing and staying compatible.

Cost if we ever drop it: the collision bridge and shader override are ours and portable; the loss is the
clipmap and instancer, which is roughly the work M8 originally budgeted. Acceptable exposure.

---

## 1. Milestone plan

Ordered by visual payoff per unit work, with two prerequisites inserted ahead of the requested order
because nothing renders without them.

### M0 — CLI harness (commit #1, no rendering work)

Full detail in §3. Nothing else may be committed before this. M0 also lands the engineering scaffolding
from §7–§9, because standards adopted later are never adopted: formatter and lint configs, the pre-commit
hook, the meta-gates (`format`, `typing`, `file_size`, `layering`, `magic_numbers`, `gate_metadata`), the
`docs/` skeleton with its README and ADR directory, and the artifact-pruning behaviour of the runner.

**Acceptance:** `tools/gate.sh smoke` boots an empty world, writes
`artifacts/shots/smoke/hero_3q.png`, prints one `HARNESS_METRIC {...}` JSON line per frame, exits 0.
Re-running twice produces byte-identical PNGs. `tools/gate.sh --list` enumerates gates.

**Visual verification:** the agent reads the PNG with the Read tool and confirms it shows the expected
solid clear-colour and a debug text overlay naming the preset and frame index.

---

### M1 — Softbody bridge + hero truck on screen (hard prerequisite for everything)

Full detail in §2. This milestone also contains the LBS-vs-FlexBody spike that decides whether the
motion-vector plan in M3 is viable, so it must not be compressed or deferred.

Scope:
- GDExtension skeleton: build `.dylib` / `.so` via `scons` + `godot-cpp`, CLI-only, no editor plugin.
- De-couple RoR's `Actor` / `Beam` / `FlexBody` from OGRE: strip `Ogre::SceneNode`, `Ogre::Entity`,
  `Ogre::HardwareVertexBuffer` and `ResourceGroupManager` calls behind an abstract
  `IRenderBridge` interface that the Godot side implements.
- Reuse RoR's `RigDef::Parser` unmodified for `.truck`.
- Write an OGRE `.mesh` / `.skeleton` binary reader in C++ inside the extension (no OGRE dependency).
- Minimal legacy shim: ZIP mod mounting, `.material` script parse → derived PBR params (§4),
  DDS/TGA/PNG/JPG textures, one `.terrn2` terrain (compatibility subject, not the showcase).
- Vertex delivery path and the skeleton-skinning decision per §2.
- Conversion cache: first load writes Godot binary resources into `user://cache/<mod-hash>/`.
- **Valley One v1** (§0.5 staging): Terrain3D installed and pinned; `tools/import_dem.gd` builds the
  valley heightmap from public-domain elevation data with the road spline and ruts carved in;
  `valley_one.gd` places blockout props, water planes, and camera anchors from the layout file;
  collision mode `Disabled` with RoR collision driven through the height-query bridge (§0.6). Ugly,
  fully drivable, final in layout.

**Acceptance:**
1. The hero truck loads from an unmodified community `.zip` and renders with legacy-equivalent
   materials (unlit-ish, diffuse-only) at 1080p.
2. The solver runs at its original substep rate on its own thread; `HARNESS_METRIC` reports
   `solver_ms`, `deform_ms`, `submit_ms` separately.
3. LBS spike gate `flexbody_lbs_error`: for 600 recorded solver frames covering a drop, a roll, and a
   wheel impact, the maximum per-vertex difference between RoR's `FlexBody` CPU deform and
   linear-blend skinning against the same node frames is **< 1 mm**, and the 99th percentile is
   < 0.2 mm. Report a histogram. A fail here changes M3's approach — see R1/R2.
4. Determinism gate: 600 frames, two runs, identical node-position hash.
5. `mod_corpus` gate over 200 archive mods: each either loads or reports a named unsupported feature;
   zero crashes, zero hangs.
6. `terrain_collision_agreement`: sampled across the whole valley including the switchbacks, the ford,
   and the rut section, the height RoR's collision sees and the height Terrain3D renders agree within a
   stated tolerance. A visual-versus-collision mismatch is the classic "wheels floating / sunk" bug and
   it must be a number, not an observation.
7. `drivability`: the scripted `switchback_climb`, `ford_crossing`, and `rut_traverse` scenarios complete
   without the actor falling through terrain, getting stuck, or exploding; solver energy stays bounded.
8. `asset_licenses` passes: every scene asset and addon has a `LICENSES/` record and a `THIRD_PARTY.md`
   entry with a version pin.

**Visual verification:** contact sheet from `--write-movie` of a 5-second drop test, eyeballed by the
agent for correct deformation silhouette; side-by-side PNG of the same frame rendered from the CPU
FlexBody path and the skinned path, plus the numeric error histogram as the real proof; the eight money
shots rendered in blockout form, which establishes the before-image the whole project is measured against.

---

### M2 — PBR + HDR + tonemap + IBL sky (requested milestone a)

Highest payoff per unit work: it is almost entirely `.gd` config plus one vehicle `.gdshader`, and it
changes every pixel on screen.

Scope:
- `WorldEnvironment` built in code: HDR pipeline, `tonemap_mode = AGX` (see decision below),
  white point and exposure in `render_cfg.gd`, auto-exposure off for gates (non-deterministic
  convergence), fixed exposure per camera preset.
- Sky: `PhysicalSkyMaterial` for clear day, `PanoramaSkyMaterial` from `.exr` HDRIs for dawn / dusk /
  overcast / night. Sky supplies IBL: radiance map for specular, `ambient_light_source = SKY` for
  diffuse. Radiance size and update mode pinned in config.
- Vehicle `.gdshader`: metallic-roughness, ORM-style parameter packing, clearcoat for automotive
  paint, per-material overrides from `material_cfg.gd`.
- Derived-map generation for legacy assets (§4): roughness from diffuse luma through a
  material-class LUT; metallic default 0 with a chrome allowlist; **no derived normal maps**.
- One `ReflectionProbe` per actor for local specular, low update rate.
- **Valley One v2** — the milestone where the scene first looks good: PBR ground, rock and bark
  materials through the Terrain3D shader override; vegetation tier 1 via `Terrain3DInstancer`; the
  staged water plane (sky reflection, refraction, depth fade, shoreline term, scrolling normals) on the
  river and lake; distance haze and valley-floor fog.
- **Weather presets** in `weather_cfg.gd`: `dawn_mist`, `noon_clear`, `overcast`, `golden_dusk`,
  `night_clear`, `fog_bank` land here; `rain_storm` completes at M6/M7 once wetness and particles exist.
  A preset is a CLI argument, so every later gate can be run under any weather.

**Decision: AgX as the default tonemapper, not ACES or Filmic.** ACES over-saturates and hue-shifts
bright vehicle paint and headlight cores; Filmic crushes the shadow ramp that makes suspension
geometry readable. AgX keeps highlight hue and gives a neutral base to grade from. ACES stays
available in config for comparison shots. Rejected: writing a custom tonemap `.gdshader` — no
per-pixel benefit and it loses Godot's built-in glow/exposure integration.

**Decision: no derived normal maps from diffuse.** Height-from-luma turns painted logos, text, and
grille decals into embossed relief, which is more visibly wrong than flat normals. Legacy assets get
geometric normals only; authored normals come with re-textured hero assets.

**Acceptance:**
1. Khronos oracle gate `pbr_spheres`: render the Khronos `MetalRoughSpheres` sample asset under a
   known HDRI and compare against the reference image shipped with `glTF-Sample-Assets`. Perceptual
   diff below threshold. This is an AI-free oracle for the BRDF and the IBL path.
2. Tonemap curve gate `tonemap_curve`: sample the rendered value of a synthetic exposure wedge and
   compare numerically against the published AgX / ACES transfer values. Tolerance stated in the gate.
3. Grey-chart gate: a MacBeth chart under a 6500 K light renders within a stated ΔE of its reference
   values.
4. No HDR clipping: the 16-bit render target histogram from the night and sun-backlit presets shows
   no clamped channel before tonemap.
5. Perf: ≤ 16.6 ms at 1080p on the dev Mac with one truck + terrain, draw calls logged.

**Visual verification:** a fixed 8-shot sheet (`hero_3q`, `hero_rear_low`, `cockpit`, `wheel_macro`,
`terrain_vista`, `sun_backlit`, `dusk`, `night`) rendered before and after, assembled by ffmpeg into
one before/after contact sheet the agent reads in a single Read call.

---

### M2b — Physical camera and the post-processing stack

Inserted here because it is the cheapest large payoff in the whole plan: almost entirely `.gd` config
plus a handful of `.gdshader` files, no new systems, and it is what makes the difference between "a
rendered scene" and "a photographed scene". Motion blur is the one piece held back to M3, because it
needs the velocity buffer.

**Decision: a physical camera, not FOV numbers.** Camera presets use `CameraAttributesPhysical` —
focal length in mm, f-stop, shutter speed, ISO-equivalent exposure — instead of a bare FOV. Reasons: the
depth of field then comes out of the lens parameters instead of being dialled by hand; exposure becomes
EV-based and therefore comparable between weather presets; and cinematography language (35 mm wide for
the valley vista, 85 mm for the wheel macro) maps directly onto the money shots. Auto-exposure is
disabled in gates, since its convergence is temporal and would make goldens non-deterministic; each
preset carries a fixed exposure.

Scope, split by colour space because the ordering matters:

*HDR-linear, before tonemap* — implemented as built-ins plus `CompositorEffect` where needed:
- Depth of field from the physical lens, with focus distance either fixed per preset or tracking the
  hero actor.
- AO and indirect: `ssao_enabled` and `ssil_enabled` wired here as part of the stack (their tuning and
  the GI scheme they belong to are M4's subject).
- Glow / bloom with threshold, levels, and a HDR-correct bleed — the thing that makes headlights and sun
  glints read as bright rather than just white.
- Screen-space sun shafts / lens flare driven by the sun's screen position and occlusion.
- Heat haze as a local screen-space distortion near exhausts.

*Display space, after tonemap and after FSR upscale* — a fullscreen canvas shader on a `CanvasLayer`:
- Colour grading through a 3D LUT (`Environment.adjustment_*`), one LUT per weather preset, plus
  contrast/saturation/brightness fallbacks.
- Vignette, film grain, subtle chromatic aberration confined to the frame edges, and lens dirt.
- Optional final sharpen where FSR's own sharpening is not enough.

Ordering is a decision, not an accident: grain, vignette, aberration, and dirt go **after** TAA and
upscaling, or TAA averages the grain away and the upscaler amplifies the aberration. DOF and motion blur
stay in HDR linear before tonemap, where their weighting is physically meaningful.

**Acceptance:**
1. `dof_coc`: for a stated focal length, f-stop, and focus distance, the measured circle-of-confusion
   diameter of a point-light target at several distances matches the thin-lens formula within a stated
   tolerance. The lens equation is the oracle; no golden image involved.
2. `exposure_ev`: doubling the shutter time or opening one f-stop changes measured scene luminance by
   exactly one stop within tolerance. Catches the classic bug where exposure is applied twice.
3. `glow_energy`: total image energy added by glow is bounded and scales monotonically with threshold;
   no glow on sub-threshold pixels.
4. `grain_after_taa`: with TAA on, grain variance measured over 60 static frames stays within a stated
   band of the TAA-off variance — proving the grain survives temporal accumulation, i.e. it really is
   applied post-resolve.
5. `lut_neutral`: an identity LUT is a no-op to within quantisation error. Catches LUT sampling and
   colour-space mistakes, which are otherwise invisible until everything looks slightly wrong.
6. Perf: the whole display-space pass ≤ 0.8 ms and DOF ≤ 1.5 ms at 1080p.

**Visual verification:** the eight money shots with the stack off versus on, in one sheet; a focus-pull
movie contact sheet on `wheel_macro_mud`; a per-effect ablation sheet (each effect disabled in turn) so
a regression can be attributed to one pass instead of guessed at.

---

### M3 — Motion vectors, then TAA, then FSR (requested milestone b)

Gated behind M1's spike. TAA must not be enabled until `mv_correctness` passes; see §2.5 for why.

Scope, in this order:
1. `mv_correctness` gate and a debug visualisation mode that renders motion vectors as colour.
2. Correct previous-frame carry for deforming actors (§2.4), including history invalidation on spawn,
   respawn, teleport, and reset.
3. Enable `Viewport.use_taa`. Tune jitter sequence length and history rejection against the gates.
4. Enable `scaling_3d_mode = FSR2` with a render scale ladder (0.5 / 0.58 / 0.67 / 0.75 / 1.0);
   FSR1 kept only as a fallback for drivers where FSR2 misbehaves.
5. **Per-object motion blur**, held back from M2b because it consumes the same velocity buffer. Stock
   Godot has no motion blur, so this is a `CompositorEffect` sampling the velocity buffer in HDR linear,
   with the blur length derived from the physical shutter speed set in M2b — so shutter angle means
   what it says. This is the single most valuable post effect for a driving game, and it is also the
   second consumer of the motion-vector work, which is a good reason to prove the buffer twice.

**Acceptance:**
1. `mv_correctness`: for a truck moving 12 m/s across the frame plus a spinning wheel, the rendered
   motion-vector buffer matches an analytically computed reference (screen-space delta of tracked
   marker vertices, computed in `.gd` from the same pose snapshots) within 0.5 px at the 99th
   percentile. Marker positions come from the solver, not from a previously captured frame.
2. `taa_no_smear`: a 90-frame movie of the truck crossing the frame; per-frame edge-energy of the
   truck silhouette must not drop more than a stated fraction versus the TAA-off run. Smear shows up
   as lost edge energy, which is measurable rather than a matter of taste.
3. `taa_history_reset`: teleporting the truck produces no ghost — the frame after the teleport differs
   from the frame before by no more than the frame two frames later does.
4. `fsr_mtf`: a Siemens-star resolution chart rendered at 0.67 scale + FSR2 resolves a stated minimum
   MTF50 relative to native. Objective sharpness, not opinion.
5. Perf: FSR2 at 0.67 scale gains ≥ 30 % frame time versus native at equal preset.
6. `motion_blur_shutter`: a marker moving at a known screen-space velocity produces a streak whose
   measured length in pixels equals velocity × shutter time within a stated tolerance, and halving the
   shutter speed halves the streak. Physics is the oracle. Also: a spinning wheel blurs tangentially,
   not radially — which is the test that catches a camera-only blur masquerading as per-object blur.

**Visual verification:** motion-vector debug PNGs; an ffmpeg contact sheet at 4×3 tiles for the
crossing shot with TAA off / TAA on / FSR2 on, in three rows, so smear and ghosting are visible in
one image; a per-frame absolute-difference montage (`ffmpeg` `tblend=difference`) which makes
trailing history light up.

---

### M4 — AO and GI (requested milestone c)

**Decision: SDFGI + SSIL + SSAO + per-actor ReflectionProbe. VoxelGI rejected for the open world,
DDGI rejected outright.**

Rationale:
- **VoxelGI** needs a bounded, baked volume. RoR terrains are kilometre-scale, so covering them costs
  either an unusable voxel size or many volumes, and the bake is a non-CLI-friendly step. Kept as an
  opt-in for enclosed set pieces only (garage, tunnel, warehouse) where it is genuinely better.
- **SDFGI** is built for large open worlds, cascades follow the camera, needs no bake, and all its
  parameters are `Environment` properties settable from `.gd` — which fits the CLI constraint exactly.
  Its real limitation is that it is static-occupancy: a deforming truck neither occludes nor bounces
  SDFGI light. Accepted, and compensated below.
- **DDGI** is not in Godot. Implementing it means probe volumes plus a scene representation to trace
  against, and stock Godot exposes no BVH or SDF to trace — so we would rebuild most of SDFGI first
  and then add probes on top. The payoff over SDFGI-plus-SSIL does not justify that, and it would
  almost certainly force the engine fork we agreed to avoid.
- The gap SDFGI leaves is exactly the deforming-body case in the brief. **SSIL** fills it: it is
  screen-space, so it is fully dynamic and free of any static assumption, and it supplies the local
  bounce under wheel arches and inside the cab. **SSAO** supplies contact darkening. A per-actor
  **ReflectionProbe** at a low update rate supplies local specular.

Scope: SDFGI cascade count / size / energy / bounce-feedback tuned per terrain in `light_cfg.gd`;
SSAO and SSIL enabled with radius and intensity per preset; light-leak mitigation via cascade sizing
and `sdfgi_normal_bias`; vehicle-interior handling.

**Acceptance:**
1. Cornell-box oracle gate `gi_cornell`: a Cornell-box scene built in `.gd` rendered by us, compared
   against a Blender Cycles path-traced render of the same geometry and materials. Compare relative
   radiance ratios between wall patches, not absolute pixels. Cycles is the AI-free oracle.
2. `gi_tunnel`: truck driven into a tunnel; interior surfaces must darken monotonically with depth,
   and the underside of the vehicle must be measurably darker than its roof by a stated ratio.
3. `ao_contact`: the wheel–ground contact region is darker than the surrounding ground by a stated
   ratio in the `wheel_macro` preset.
4. No SDFGI flicker: over 120 frames with the camera moving through a cascade boundary, frame-to-frame
   mean luminance change stays below a stated threshold.
5. Perf: combined SDFGI + SSIL + SSAO cost ≤ 5 ms at 1080p, logged per-effect.

**Visual verification:** GI-on / GI-off contact sheets for tunnel, garage, overcast terrain; a
Cycles-versus-us side-by-side of the Cornell box.

---

### M5 — Shadow overhaul, IES headlights, volumetric shafts (requested milestone d)

Scope:
- Directional shadows: 4-split PSSM with split distances, blend, normal bias, and `light_size` soft
  shadows tuned in `light_cfg.gd`; 4096 atlas; per-cascade texel-density targets stated in config.
- Deforming-mesh shadow artefacts: thin truck panels peter-pan or self-shadow-acne under a single
  global bias. Fix with per-material bias plus double-sided shadow casting on thin panels, both driven
  from `material_cfg.gd`, and a dedicated gate.
- Headlights: shadow-casting `SpotLight3D` per lamp, with an IES-derived beam.
- Volumetric fog with per-light `light_volumetric_fog_energy` for shafts; interaction with TAA
  explicitly tested, because volumetric fog has its own temporal filter and can beat against the TAA
  jitter sequence.

**Decision: IES via offline-generated projector cookies, not an engine IES loader.** Godot has no IES
support and adding a real photometric-profile path to `SpotLight3D` is an engine change. Instead a
CLI tool converts `.ies` into a 256×256 projector texture plus angular-attenuation parameters, and the
light uses `light_projector`. This reproduces the beam *pattern* — the visible part — without a fork.
Rejected: faking beams with hand-painted cookies (no photometric basis, so nothing to verify against);
rejected: forking to parse IES (buys accuracy nobody can see at 1080p through fog).

**Acceptance:**
1. `ies_beam` gate: project the generated cookie onto a flat wall at a fixed distance, extract the
   horizontal and vertical intensity profiles, and compare against the candela values read from the
   `.ies` file itself by an independent third-party IES viewer's exported plot. Correlation and
   beam-angle error thresholds stated. The `.ies` file and the external viewer are the oracle.
2. `shadow_texel_density`: measured shadow texels per metre at 5 m / 20 m / 80 m / 300 m meets stated
   minima; split boundaries are not visible as a luminance step above a stated threshold.
3. `shadow_thin_panel`: no acne and no visible detachment on the hood and door panels of the hero
   truck across a full solar-angle sweep of 12 shots.
4. `volumetric_shafts`: headlights at night through fog produce a measurable luminance gradient along
   the beam axis; the shaft is stable — frame-to-frame variance below a stated threshold with TAA on.
5. Perf: shadows + volumetric fog ≤ 6 ms at 1080p with two headlights casting.

**Visual verification:** solar-angle sweep sheet; night headlight sheet at three fog densities; a
TAA-on movie contact sheet checked for fog shimmer.

---

### M6 — SSR plus a wetness/dirt layer with decals (requested milestone e)

Scope:
- `Environment.ssr_enabled` with max steps / fade / depth tolerance in config; roughness-aware fade;
  fallback to the ReflectionProbe and sky radiance where SSR misses.
- A wetness/dirt layer in the vehicle and terrain shaders: roughness reduction plus normal flattening
  plus a darkening albedo term, driven by a mask.
- Terrain decals: `Decal` nodes with `texture_orm` for puddles, tyre marks, oil, so they write
  roughness and normal, not just albedo.

**Correction to the brief, stated plainly: Godot 4 has no deferred renderer, so there are no deferred
decals.** What exists are clustered forward `Decal` nodes, which are world-space box projections.
Functionally they cover the terrain case well — including the roughness write that wetness needs
through `texture_orm`. They do **not** cover vehicles: a world-space projection cannot stick to a
truck whose vertices move every frame, and re-parenting decals to the actor still projects through
deforming geometry incorrectly.

**Decision: vehicle grime is a per-actor UV-space accumulation texture, not a decal.** Each actor owns
a small R8 or RG8 "grime buffer" in its own UV space. Splats (mud thrown by a wheel, water from a
puddle crossing, spray from another vehicle) are written into it by a compute or a quad pass in UV
space, with an evaporation/wash-off decay term. The vehicle shader samples it. This is object-space by
construction, survives arbitrary deformation, is cheap, and is inspectable — the buffer can be dumped
to PNG by the harness, which makes it testable. Decals stay for terrain only.

**Acceptance:**
1. `ssr_flatwater`: a mirror-flat puddle reflects a known marker object at the geometrically correct
   screen position within a stated pixel error — computed analytically, not from a golden.
2. `ssr_rough_fade`: a roughness ramp strip shows SSR contribution decreasing monotonically with
   roughness and handing off to the probe without a visible seam step.
3. `wetness_fresnel`: wet asphalt at grazing angle is measurably brighter than dry at the same
   exposure, and the ratio follows a stated Fresnel curve within tolerance.
4. `grime_uv_stability`: drive the truck through a mud patch, then subject it to a violent roll; the
   grime pattern must stay locked to the same UV region — per-texel drift below a stated threshold
   across 300 frames.
5. `decal_orm`: a puddle decal lowers the terrain roughness in its footprint and nowhere outside it.
6. Perf: SSR ≤ 3 ms at 1080p; grime accumulation ≤ 0.3 ms per actor.

**Visual verification:** wet/dry before-after sheets in the `wet_asphalt` and `dusk` presets; a
dumped grime buffer PNG next to the rendered truck; a movie contact sheet of the mud-then-roll test.

---

### M7 — Lit particle rewrite: dust, spray, tyre smoke (requested milestone f)

**Decision: a two-tier system — GPU-particle lit quads for discrete droplets and debris, FogVolume
density fields for the soft continuous media (dust clouds, tyre smoke).** One system cannot do both
well. Sprite particles look wrong for tyre smoke because smoke needs to receive shadowing and
scattering through its own volume, which billboards cannot do; `FogVolume` with a 3D-noise density
shader sits in Godot's volumetric fog froxel grid, so it receives directional-light scattering,
shadowing, and the volumetric contribution of the headlights for free — which is exactly the look
that is missing today. Conversely, water spray and gravel need sharp, fast, individually-lit
elements, which is what `GPUParticles3D` with lit quad meshes gives.

Scope:
- Emission driven from the solver: per-wheel contact patch, slip ratio, load, surface type, and water
  depth are already available in RoR's wheel model and become emitter parameters over the bridge.
- `GPUParticles3D` with custom process `.gdshader`, lit spatial material on the quads, soft depth
  fade, collision against the depth buffer for cheap ground interaction.
- `FogVolume` per dust source with a density `.gdshader` advected by a simple wind field; lifetime and
  dissipation in config.
- Retire OGRE `.particle` scripts; legacy ones map to a default effect by name class (§5).

**Acceptance:**
1. `particle_lit`: the same dust plume rendered under a low sun from the front and from behind shows a
   measurable brightness inversion — i.e. it is genuinely lit and scattering, not a flat sprite.
2. `smoke_shadowed`: a tyre-smoke volume under a directional light casts and receives shadowing;
   luminance along the light axis decreases monotonically through the volume.
3. `particle_emission_coupling`: emission rate correlates with solver slip ratio over a burnout test
   within a stated correlation coefficient — the effect is driven by the sim, not a timer.
4. `particle_taa`: with TAA on, a static-camera plume shows no frame-to-frame boiling above a stated
   variance threshold.
5. Perf: 20 000 live particles plus three fog volumes ≤ 2.5 ms at 1080p.

**Visual verification:** front-lit versus back-lit plume pair; burnout movie contact sheet; a
night-with-headlights dust shot, which is the single most convincing frame this milestone produces.

---

### M8 — FFT ocean and terrain virtual texturing (requested milestone g)

Last, deliberately: the most work per visible pixel for a one-truck demo, and it is the milestone most
likely to need a fork.

Scope:
- Ocean: Tessendorf FFT in `RenderingDevice` compute (`.glsl`), producing displacement, normal, and
  foam/Jacobian maps into texture arrays for three cascade scales; a clipmapped water mesh displaced
  in the vertex shader; shoreline depth fade; SSR reuse from M6 for reflection.
- Buoyancy stays in the solver: the bridge exposes a water-height query so RoR's existing buoyancy
  reads the FFT surface rather than a flat plane. The GPU-computed height must be readable
  cheaply — decision: the solver samples the same spectrum on the CPU at low resolution rather than
  reading back GPU buffers, because a readback stalls the frame and buoyancy does not need the
  high-frequency detail. Accept the small CPU/GPU divergence and gate it.
- Terrain texturing: **decision — Terrain3D's clipmap and 32-texture splat array is the answer; true
  virtual texturing only if the texel budget provably fails.** Adopting Terrain3D (§0.6) already deleted
  the mesh, LOD, and splat work this milestone originally carried, so what remains here is raising texel
  density in our shader override: stochastic/rotated tiling to kill visible repeats, detail-texture
  blending by distance and slope, and triplanar projection on cliffs. Real VT needs a feedback buffer, an
  indirection texture, and a page-table update path, and stock Godot exposes no hook to run the feedback
  pass inside the main geometry pass — it lands on `CompositorEffect` at best and a fork at worst. Only
  pursue it if `terrain_texel_density` fails after the cheap measures. Revisit with measurements, not
  vibes.

**Acceptance:**
1. `ocean_spectrum`: the CPU and GPU height fields agree within a stated RMS at matched sample points;
   the statistical wave-height distribution matches the Pierson–Moskowitz spectrum the generator was
   parameterised with, checked numerically against an independent Python/NumPy implementation of the
   same spectrum — the published spectrum is the oracle.
2. `ocean_buoyancy`: a floating actor's waterline tracks the visual surface within a stated tolerance
   across 600 frames; no visible interpenetration in the movie.
3. `terrain_texel_density`: measured terrain texels per metre at the camera meets stated minima at
   5 m / 50 m / 500 m; no visible tiling repeat in the `terrain_vista` preset above a stated
   autocorrelation threshold.
4. Perf: ocean ≤ 3 ms, terrain ≤ 4 ms at 1080p.

**Visual verification:** ocean movie contact sheet at three sea states; a waterline close-up sequence;
a terrain vista sheet at three times of day.

---

## 2. The softbody-to-Godot bridge

This is the load-bearing part of the plan. Get it wrong and M3 is impossible and M1 is slow.

### 2.1 What is actually being moved

Per actor: up to roughly a thousand solver nodes and several thousand beams, stepped at RoR's
existing high substep rate. Visual geometry is a much larger set of vertices — order tens of thousands
for a detailed truck — bound to the nodes by RoR's `FlexBody` locators (each vertex referenced to a
small set of nodes forming a local frame) and by `FlexMeshWheel` for procedurally generated tyre and
rim geometry. So the per-frame data flow is "solver nodes → vertex positions", and the question is
where that expansion happens.

### 2.2 Decision: skin it, do not stream it

**Primary path: bind each solver node to a `Skeleton3D` bone and let Godot's own GPU skinning do the
deformation.** The actor's visual mesh is authored (at load time, in the shim) with skin weights that
reproduce the `FlexBody` locator as a linear blend of three or four bones. Each frame the bridge writes
only bone transforms — about a thousand per actor — and the GPU expands them to vertices.

Why this and not per-frame vertex streaming:
- It removes the per-frame vertex upload entirely. A thousand bone transforms is tens of kilobytes per
  actor per frame; the equivalent vertex stream for a detailed truck is hundreds of kilobytes per
  actor per frame, an order of magnitude more, and it scales with mesh detail rather than with rig
  complexity. That matters the moment anyone raises the poly count, which is the whole point of the
  rewrite.
- **It makes motion vectors work in stock Godot.** Godot already generates motion vectors for skinned
  meshes from the previous frame's bone transforms. That is precisely the data we have. A mesh whose
  vertex buffer we rewrite by hand gets no such treatment — see §2.5.
- The deformation runs on the GPU instead of consuming CPU that the solver wants.

The cost of this decision is that it constrains the deformation to what linear blend skinning can
express. RoR's `FlexBody` builds a local frame per vertex and is not literally LBS, so the two may
disagree. That is why M1 contains the `flexbody_lbs_error` gate with a stated numeric threshold,
before any rendering work depends on it. If the spike fails, see R1.

### 2.3 Fallback path: streamed vertex regions

If the spike fails for some geometry classes (most likely candidates: `FlexMeshWheel`, and any mesh
whose locators were authored with extreme bend), those meshes fall back to CPU deform plus streamed
vertex updates:

- `ArrayMesh` surfaces created with the dynamic-update flag.
- Deform on `WorkerThreadPool` group tasks, one task per surface, writing into triple-buffered
  staging `PackedByteArray`s so the solver thread never blocks on the renderer.
- A single main-thread submit pass per frame calling `RenderingServer.mesh_surface_update_vertex_region`
  per surface. Godot keeps position/normal/tangent in the vertex region and UV/colour in a separate
  attribute region, so updating only the vertex region touches exactly the data that changes and never
  disturbs UVs — that is the reason to use the region update rather than rebuilding the surface.
- Surfaces are merged by material at load time to minimise the number of submit calls, because at this
  scale the per-call overhead, not the bandwidth, is what bites.
- If the submit pass shows up in the profile, move the upload into
  `RenderingServer.call_on_render_thread` and write through `RenderingDevice` buffer updates.

### 2.4 Decision: GPU compute deform is rejected for v1

A compute shader reading node transforms and writing vertex buffers is attractive and would also solve
motion vectors by writing both current and previous position streams. It is rejected for v1 because
stock Godot exposes no public way to obtain the `RID` of an `ArrayMesh` surface's vertex buffer and
bind it as a compute storage buffer. Working around that means owning the whole mesh path through
`RenderingDevice` — which stock Godot cannot then draw as a normal shadow-casting, GI-participating
mesh — or forking. Since the skinning path gets the same GPU-side expansion and the same motion
vectors with none of that, compute deform buys nothing it does not already have. Revisit only if
skinning fails *and* streaming is measured as the bottleneck.

### 2.5 How previous-frame positions are carried

This is the part that decides whether TAA and FSR smear moving trucks, and it is subtle in three
separate ways.

**Bulk motion must live in the instance transform, not in the vertices.** RoR effectively deforms
vertices in world space, so if that is carried over naively the actor's `Node3D` transform never
changes and Godot computes zero motion for a truck crossing the screen at 12 m/s — the worst possible
outcome, and one that looks like "TAA is broken" rather than "the bridge is wrong". Therefore: the
bridge computes a per-actor reference frame each render frame from RoR's existing reference nodes,
sets the actor's `Node3D` transform to it, and expresses all bone transforms **in actor-local space**.
Stock Godot then handles the dominant motion term for free, and skinning handles the residual.

**Snapshots are taken at render time, not at solver time.** The solver runs far faster than the
renderer, so the pose that must be differenced is the pose that was *rendered*, not the last substep
computed. The bridge keeps a two-entry ring of render poses: `render_pose[cur]`, produced by
interpolating solver substeps to the frame's presentation time, and `render_pose[prev]`, which is
simply the previous frame's `render_pose[cur]`. Motion vectors derived from raw substep state would be
wrong by a fraction of a frame everywhere and badly wrong under variable frame time. Godot's skinning
motion-vector path consumes exactly this: previous-frame bone transforms.

**History must be explicitly invalidated on discontinuities.** Spawn, respawn, teleport, reset, and
any solver re-initialisation make `prev` meaningless; differencing across one produces a full-screen
streak. The bridge exposes `invalidate_history(actor)`, which sets `prev = cur` for that actor and
requests that the renderer reject TAA history for the affected pixels, and every discontinuity site in
the ported solver calls it. The `taa_history_reset` gate in M3 exists specifically to prove this.

**Wheels.** Tyre rotation is the fastest screen-space motion in the game and the thing TAA will
destroy first. Each wheel gets its own bone (or bone set), so its spin is carried in bone transforms
and gets correct motion vectors by the same mechanism — with no special case.

### 2.6 Prerequisite status and the risk of deferring it

The bridge, including the LBS spike and the previous-frame carry, is a **hard prerequisite for
milestone (b)**. Nothing about it can be back-filled later, for a specific reason:

If TAA or FSR is enabled before motion vectors are correct, the truck — the only object the player is
looking at — smears and ghosts, wheels turn to mush, and *the rest of the image looks fine*. The
failure is therefore misattributed: time gets spent tuning TAA parameters, jitter sequences, and
history-rejection heuristics that cannot possibly fix a missing input. On top of that, ghosting makes
every golden image non-deterministic in exactly the region of interest, so the harness starts
reporting noise and the agent loses its only feedback channel. Worst case, the project concludes "TAA
doesn't work for softbody" and ships without modern AA or an upscaler, which forfeits milestones (b)
and most of the perf headroom that pays for (c) through (g).

Hence the ordering rule: `mv_correctness` is a gate, and `use_taa` stays false in config until it
passes.

---

## 3. The CLI harness — commit #1

Nothing else is committed first. The harness is what makes a CLI-only, no-human-eyes workflow able to
tell whether a rendering change helped.

### 3.1 Shape

- `res://harness/harness.gd` — autoload. Parses arguments after `--` via
  `OS.get_cmdline_user_args()`. Owns the run loop, capture, metrics, and exit code.
- `res://harness/cameras.gd` — named camera presets as a const dictionary: position, look-at target
  (node path or world anchor from the Valley One layout), focal length, f-stop, shutter, fixed exposure,
  and which scenario and weather preset to build. Covers the eight money shots (§0.5) —
  `valley_vista`, `switchback_backlit`, `ford_crossing`, `tunnel_headlights`, `rock_traverse`,
  `lake_dusk`, `rain_road`, `wheel_macro_mud` — plus the diagnostic presets `hero_3q`, `hero_rear_low`,
  `cockpit`, `chase`, `overdraw_top`.
- `res://harness/scenarios.gd` — deterministic scripted scenarios: `static`, `drop`, `roll`,
  `crossing`, `burnout`, `mud_then_roll`, `teleport`, `tunnel_drive`, `switchback_climb`,
  `ford_crossing`, `rut_traverse`. Each is a fixed sequence of solver inputs over a fixed tick count.
- `--weather <preset>` selects any `weather_cfg.gd` entry, so any gate runs under any weather and time
  of day without a second scene.
- `res://harness/gates/*.gd` — one file per gate, declaring its scenario, presets, capture frames,
  thresholds, and which oracle it compares against.
- `tools/gate.sh` — the only entry point the agent uses. Runs the engine, collects artifacts, runs
  diffs, prints a PASS/FAIL table, exits non-zero on failure.

### 3.2 Determinism

`--seed <n>` seeds a single explicit `RandomNumberGenerator`; global `randi()` is banned by a grep
gate. `--tick <hz>` pins `Engine.physics_ticks_per_second` and the solver substep count per tick.
`--deterministic` additionally forces the solver to one thread, because threaded floating-point
reduction order is a real source of golden-image flicker. `--fixed-fps 60` plus a fixed frame count
replaces wall-clock pacing, so capture happens at a known simulation time.

**Convergence is part of the contract.** TAA history, FSR2 history, SDFGI cascade population,
volumetric-fog temporal filtering, and auto-exposure all need multiple frames to settle. Every capture
specifies `--converge <frames>` (default 32), which is recorded in the manifest, and gates that
involve temporal effects capture at two different convergence counts so that "still converging" is
distinguishable from "wrong".

### 3.3 Output the agent can actually read

- `--shot <preset>` → after convergence, `get_viewport().get_texture().get_image().save_png()` to
  `artifacts/shots/<gate>/<preset>.png`, plus a sibling `.json` manifest with engine version,
  `--rendering-driver` string, GPU name, git SHA, seed, tick, convergence count, and scenario frame.
  The agent reads the PNG directly.
- `--write-movie <path.avi>` with `--fixed-fps` for motion, then ffmpeg for the two forms that make
  motion legible in a still image: a tiled contact sheet (`fps`, `tile=4x3`, `scale`) and a
  consecutive-frame difference montage (`tblend=all_mode=difference`), which is how ghosting, smear,
  and particle boiling get seen rather than guessed at.
- Debug visualisation modes selectable from the CLI, each a full-screen `.gdshader`: motion vectors as
  colour, depth, roughness, metallic, normals, SSR mask, grime buffer, shadow cascade index,
  overdraw. These are how the agent debugs a wrong image instead of staring at a beauty render.
- Metrics: one line per frame on stdout, `HARNESS_METRIC {json}`, so it is greppable and
  machine-parsable. Contents: frame index, total frame ms, `solver_ms`, `deform_ms`, `submit_ms`,
  draw calls, primitives, video memory, texture memory, and per-effect GPU timings where available.
  At run end, a summary block with p50 and p99 — never the mean, because the mean hides the hitches
  that actually matter. `--frame-times <csv>` writes the raw series.

### 3.4 Gating

- `tools/imgdiff.gd` run under `godot --headless --script`: perceptual comparison on luma with a small
  pre-blur to absorb driver-level nondeterminism, reporting an SSIM-class score plus worst-region
  coordinates so a failure says *where*. Headless is fine here — headless cannot render, but it can
  load and process `Image`s, which is all the differ needs. One toolchain, no Python dependency.
- Per-gate thresholds live in the gate's `.gd` file, with a comment stating why that number.
- **Golden updates require `--update-golden` plus a human approval line in the manifest.** A gate may
  not write its own expectation.
- **Outside oracles, preferred over goldens wherever one exists:** Khronos `glTF-Sample-Assets`
  reference images for the BRDF and IBL; a Blender Cycles render for GI; published AgX/ACES transfer
  values for the tonemap; MacBeth reference values for colour; a third-party IES viewer's photometric
  plot for headlights; a NumPy implementation of the Pierson–Moskowitz spectrum for the ocean; a
  Siemens-star MTF measurement for upscaler sharpness; analytically computed screen-space deltas for
  motion vectors. Goldens are the fallback, not the default.

### 3.5 Platform reality

**Decision: macOS only for now. Linux is deferred, not designed out.** Standing up an `xvfb` + lavapipe
CI lane costs real time, gates nothing the dev Mac cannot gate, and lavapipe cannot even run several
features this plan depends on. So: one platform, one authority, full speed. Linux comes back when there
is a second developer, a build farm, or a release to ship — and the plan is written so that costs a few
days, not a refactor.

`godot --headless` renders nothing, so every image gate needs a real window. On the dev Mac that means
gates run with a visible window; there is no surfaceless GPU path on macOS. Consequences, accepted:

- **macOS on the dev Mac is the sole authority for everything: pixels, timings, and logic gates.**
  `tools/gate.sh --all` runs the entire suite locally, including the non-image gates that would have
  gone to CI (determinism hashes, mod corpus, scene purity, `randi()` ban, solver unit tests, counter
  regressions). No remote lane to keep green, no cross-platform golden reconciliation.
- The rendering driver string, GPU name, and OS version are still recorded in every manifest, and the
  differ still *refuses to compare* across differing driver or GPU strings rather than silently
  reporting a diff. This is cheap now and is exactly what makes adding a second platform later
  non-catastrophic — including a Metal-versus-MoltenVK switch on the same machine.
- **What we keep doing for a future Linux lane, because it is free if done from the start:** no
  Metal-specific or macOS-specific code paths, no absolute macOS paths, shaders kept to portable GLSL
  as Godot accepts it, `tools/gate.sh` parameterised by platform profile with a single `mac` profile
  defined today, and every gate declaring whether it needs a GPU. The moment a Linux box exists, the
  non-image gates run there unchanged.
- Consequence to state up front: goldens can only be captured and regenerated on the dev Mac. Given the
  no-self-approval rule, that is a feature rather than a limitation.

### 3.6 Human-in-the-loop mode

The same harness that captures PNGs also hands the machine to the user. One command:

```
tools/play.sh                       # Valley One, hero truck, last used weather, windowed, driveable
tools/play.sh --weather rain_storm  # any weather/time preset
tools/play.sh --at ford_crossing    # spawn at any money-shot anchor
tools/play.sh --compare M2          # A/B against a recorded milestone state
```

What the window gives the user:

- **Drive the truck** with RoR's normal controls, and a free-fly camera toggle so they can inspect from
  anywhere — including the cinematic camera rig used by the money shots, so they can see the shot live
  rather than as a still.
- **Live ablation hotkeys.** One key per effect: TAA, FSR, motion blur, DOF, SSR, SSAO, SSIL, SDFGI,
  shadows, volumetric fog, grain/grade, wetness, particles. Toggling on the fly is how a human tells
  "this effect is wrong" from "this scene is wrong", and it is far more informative than a static
  ablation sheet.
- **Weather and time-of-day cycling** on keys, so lighting can be swept without restarting.
- **Live HUD**: frame ms with p99, draw calls, VRAM, `solver_ms` / `deform_ms` / `submit_ms`, active
  effect list. Toggleable so it is out of the way for looking at the image.
- **Screenshot key** writing to `artifacts/human/<date>/`, so the user can point at a frame instead of
  describing it.
- **Session recording.** `--record <name>` captures the input stream and, because the solver is
  deterministic, that recording replays exactly: `tools/gate.sh replay:<name>`. This is the important
  part — a problem the user finds while driving becomes a deterministic regression scenario, and from
  then on the automated suite protects the thing a human noticed once. Human attention is the scarce
  resource; spend it on finding new problems, never on re-checking old ones.

**Per-milestone human sessions.** Every milestone below is human-gated except M0, which has nothing to
look at:

| Milestone | What the user is asked to judge |
| --- | --- |
| M0 | Not human-gated. Harness only. |
| M1 | Does it drive? Switchbacks, ford, ruts, rocks. Deformation feel versus current RoR — the one thing only a long-time player can judge. Terrain scale and road width. Layout sign-off, since the layout freezes here. |
| M2 | Does the scene look good. Weather presets swept by key. Legacy materials that read wrong (chrome, glass, rubber) — noted by name into the material override table. |
| M2b | Camera feel: focal lengths, DOF amount, grain and grade strength. These are taste calls and cannot be gated numerically. |
| M3 | The critical one: drive fast, look for smear on the truck and mush on the wheels, toggle TAA/FSR/motion blur live, and try each FSR scale to pick the default ladder rung. |
| M4 | Drive into the tunnel and under the overhang. Does indirect light look present without looking flat or leaky. |
| M5 | Night drive with headlights. Beam shape, shadow quality at speed, shaft density in fog. |
| M6 | Ford crossing and rain: wetness onset and dry-off timing, grime build-up and wash-off rate, reflection plausibility. |
| M7 | Burnout, mud, spray, dust in low sun. Particle density and lifetime are pure taste. |
| M8 | Lake at three sea states, buoyancy feel with a floating actor, terrain detail while driving. |
| Hero re-texture | Side-by-side with the legacy truck in the same shot. |

Each session ends with the user's verdict recorded in the milestone's log, plus any finding converted
into a gate or a named deferral.

---

## 4. Asset pipeline

### 4.1 Tooling decision

All conversion tools are `.gd` scripts run as `godot --headless --script tools/<name>.gd`. No Python,
no separate toolchain, and the same code paths as the runtime shim, so a conversion bug is one bug and
not two. Headless is suitable because conversion is `Image` and file I/O, not rendering.

### 4.2 Legacy material conversion (the thing that decides how the archive looks)

Legacy assets are diffuse-only, 512–1024, low-poly. Derived parameters:

- **Material class drives everything the legacy format never stored.** Each legacy material is
  assigned a class (car paint, chrome, glass, rubber/tyre, leather/cloth, plastic, rust, lamp lens,
  carbon) and the class supplies metallic, roughness, clearcoat, IOR, transmission, sheen and
  anisotropy. The mod's diffuse texture stays as albedo, untouched. Classification trusts, in order:
  the `.material` script itself (specular colour and shininess map onto roughness; `scene_blend
  alpha_blend` means glass or decal; `cull_hardware none` means a thin panel — authored data, not a
  guess), then material/texture/submesh names, then image statistics, then a sidecar override placed
  beside the mod. Full reasoning and the rejected alternatives are in
  `decisions/0001-legacy-material-classification.md`.
- **Baked-in lighting is a known limitation, not a solved problem.** Legacy diffuse maps often have
  shading, AO and specular highlights painted in, which double-shades under IBL. De-lighting is
  opt-in per material rather than applied across the library: for assets we do not own, a wrong
  automatic correction is worse than an honest limitation.
- **Metallic** defaults to 0 with an explicit chrome/bare-metal allowlist. Guessing metallic from
  images is the fastest way to make everything look like foil.
- **Normal maps: none derived.** Stated in M2 and repeated here because it will be tempting:
  height-from-luma embosses logos and lettering, which is worse than flat.
- **AO: none derived.** No reliable source.
- **Emission** from an explicit name list (lights, gauges, displays).
- Per-material overrides land in a sidecar resource next to the mod, never by editing the mod.

### 4.3 Geometry

- LOD chains are generated, not authored: `ImporterMesh.generate_lods()` at conversion time, with
  LOD0 kept as the original geometry. Hand-authoring LODs for a community archive is not a finite task.
- Tangents generated where UVs exist; meshes without UVs get a flat fallback material and are logged.
- Surfaces merged by material per actor to cut submit and draw-call counts.

### 4.4 HDRIs and sky

A small curated set — clear day, dawn, dusk, overcast, night — from a CC0 source, converted to `.exr`
and used as `PanoramaSkyMaterial`, with `PhysicalSkyMaterial` for the parameterised clear-sky case.
Radiance map size and update mode are pinned in `render_cfg.gd`, because radiance regeneration cost
and IBL specular quality trade directly against each other and both show up in gates.

### 4.5 The existing community library

Runtime shim, as decided, with a conversion cache. Components:

1. Mod mounting: `.zip` archives with OGRE-style resource paths.
2. `.truck` and friends: RoR's own `RigDef::Parser`, unmodified, inside the GDExtension. **The
   node/beam format is preserved exactly.**
3. OGRE `.mesh` / `.skeleton` binary reader, written fresh in C++ with no OGRE dependency.
4. OGRE `.material` script parser → texture units and a handful of flags → derived PBR per §4.2.
5. Textures: DDS, TGA, PNG, JPG.
6. Terrain: `.terrn2` / `.otc` heightmaps, splat layers, object placement.
7. AngelScript terrain scripts keep running inside the GDExtension — the interpreter is already part
   of RoR — with its host API shimmed onto Godot.
8. **Conversion cache**: the first load of a mod writes Godot binary resources plus the derived
   material set and generated LODs into `user://cache/<content-hash>/`. Later loads read the cache.
   This is the compromise that makes a runtime shim affordable: shim ergonomics for the mod author,
   converted-asset load times in practice.

Scope control: the demo needs one truck and one terrain. Breadth is proven by the `mod_corpus` gate,
which asserts only that each of a few hundred archive mods loads or fails cleanly with a named
unsupported feature. Fidelity across the archive is explicitly not a demo deliverable.

---

## 5. Modding story

### What is preserved, unchanged

- `.truck` / `.load` / `.airplane` / `.boat` / `.trailer` node-beam definitions — the format mod
  authors actually own and understand. Parsed by RoR's own parser. No migration, no re-export.
- OGRE `.mesh` geometry and skeletons.
- Existing texture files.
- Terrain `.terrn2` / `.otc` and object placement.
- AngelScript terrain scripts.
- `.zip` packaging and distribution. Existing downloads keep working.

### What degrades automatically (loads, looks different)

- `.material` scripts: texture units and simple flags are honoured; techniques, passes, blend
  states, and shader references are ignored. The result is a derived PBR material, which will often
  look *better* and sometimes look wrong. Fixable by the author with a sidecar override, not by
  editing their `.material`.
- OGRE `.particle` scripts: mapped to a default effect chosen by name class (dust / smoke / spray /
  sparks). Parameters are not carried over.
- Anything relying on OGRE's fixed-function or legacy lighting model will shift, because the whole
  point is that the lighting model changed.

### What breaks outright

- Custom OGRE shaders (`.program`, Cg, legacy GLSL). No translation path exists and inventing one is
  not worth it. Replacement: `.gdshader`.
- OGRE overlays / legacy HUD definitions.
- Anything depending on OGRE-specific runtime API behaviour through scripting.

### What replaces them

- Materials: an optional sidecar override resource per material, authored as text, plus documented
  material classes so authors can opt into correct metallic/roughness without touching their mesh.
- Shaders: `.gdshader`, with a documented set of vehicle/terrain shader entry points and a stable
  uniform contract so mods are not broken by internal changes.
- Particles: scene-based effects plus a small declarative emitter description bound to solver
  quantities (slip, load, water depth), which is strictly more capable than the old scripts.
- Authoring: mod authors may use the full Godot editor. The CLI-only constraint is ours, not theirs —
  worth saying explicitly, because it is the obvious thing for the community to worry about.

### The compatibility promise, stated in tiers

Tier 1 loads unmodified and is guaranteed: rigs, meshes, textures, terrains, terrain scripts.
Tier 2 loads degraded and is best-effort: materials, particles.
Tier 3 does not load and will not: custom OGRE shaders, overlays.

Publishing these tiers early is the single cheapest thing that keeps mod authors on side, because the
thing they fear is silent breakage, not documented breakage.

---

## 6. Risks, ranked, with the earliest de-risking step

**R1 — `FlexBody` deformation is not expressible as linear blend skinning.** Kills the skinning path,
which is the foundation of both the bridge and the motion-vector plan. *Earliest de-risk:* the
`flexbody_lbs_error` gate in M1, before any rendering work. *If it fails:* fall back to streamed
vertex regions (§2.3) for the affected geometry classes and solve motion vectors by R2's fallback,
which costs roughly one extra milestone of work and some quality.

**R2 — Motion vectors for streamed-vertex meshes have no stock-Godot path.** *Earliest de-risk:* the
`mv_correctness` gate, authored in M1 alongside the spike so the answer is known before M3 starts.
*Ladder, in order:* (a) skinning, which gets it free; (b) a custom velocity pass plus a hand-written
TAA as a `CompositorEffect`, which works stock but means owning a TAA and gives up Godot's built-in
TAA/FSR2 integration; (c) a minimal engine patch adding a previous-position vertex stream to the
standard velocity prepass — the last resort we agreed to, kept as a listed patch under `patches/`
with a rebase gate.

**R3 — CLI-only development with no visual feedback means tuning blind.** This is the risk that makes
every other visual milestone unverifiable. *Earliest de-risk:* the harness is commit #1, and every
milestone's acceptance criteria are expressed as an image or a number the agent can read.

**R4 — Draw-call and bandwidth bound again, having rewritten specifically to escape that.** *Earliest
de-risk:* `HARNESS_METRIC` reports draw calls, primitives, and per-stage timings from M1 onward, with
counter-based regression gates that are GPU-independent. Surface merging by material and the
skinning path (which removes the vertex upload entirely) are the structural mitigations.

**R5 — Single-platform development hides portability breakage until Linux is added.** macOS-only is the
deliberate call for speed, and the cost is that Metal-specific behaviour, path assumptions, and
non-portable shader constructs can accumulate invisibly. *Earliest de-risk:* the portability rules in
§3.5 are in force from M0 (no platform-specific code paths, no absolute paths, portable shaders, gates
declaring GPU need, `gate.sh` already parameterised by platform profile) and the driver/GPU string is
recorded in every manifest so a backend change is detected rather than silently diffed. Also cheap and
worth doing periodically: run the suite under Vulkan/MoltenVK as well as Metal on the same machine,
which catches most backend-specific assumptions without any Linux hardware.

**R6 — The legacy shim's scope explodes across fifteen years of malformed mods.** *Earliest de-risk:*
the `mod_corpus` gate in M1 with a deliberately weak assertion (loads or fails cleanly), plus a hard
rule that only the hero truck and one terrain are fidelity targets for the demo.

**R7 — SDFGI ignores dynamic bodies, so the truck gets no bounce and casts no indirect occlusion.**
Exactly the case the brief cares about. *Earliest de-risk:* M4's `gi_tunnel` gate is designed to
expose it, and the SSIL + SSAO + per-actor `ReflectionProbe` combination is planned as the answer from
the start rather than bolted on after it looks wrong.

**R8 — Floating-point non-determinism in the threaded solver makes golden images flicker.** *Earliest
de-risk:* M0 ships `--deterministic` (single-threaded solver, fixed substeps) and M1 adds a
node-position hash gate over 600 frames run twice.

**R9 — Godot version churn, and fork creep if the ladder in R2 reaches its last rung.** *Earliest
de-risk:* pin an exact Godot tag and commit hash in the repository from M0; any patch lives as a file
under `patches/` with a gate that re-applies it against the pinned tag, so the patch set's size is
always visible rather than accumulating quietly.

**R10 — The visual ceiling is the assets, not the renderer.** 512–1024 diffuse-only textures on
low-poly geometry will still read as 2010 after PBR lands, which risks the conclusion that the
rewrite did not work. *Earliest de-risk:* M2's acceptance criteria are deliberately about lighting
correctness against outside references, not about the truck looking modern; and a hero-asset
re-texture is scheduled as its own milestone immediately after M3, so there is one asset that shows
what the renderer can actually do.

**R11 — Asset licensing, especially engine-locked content.** Converting an Unreal-marketplace or
Megascans environment into the project would poison it in a way that survives conversion and is only
discovered at release. *Earliest de-risk:* the `asset_licenses` gate and `THIRD_PARTY.md` in M1, the
approval-before-adoption rule in §0, and an explicit named rejection of engine-locked sources.

**R12 — Third-party addon churn moves every golden image.** Terrain3D and any later addon ships shaders;
an upstream update silently changes pixels and invalidates the golden set. *Earliest de-risk:* exact
version pins in `THIRD_PARTY.md` from M1, our terrain shader override tracked as a patch against a
specific release, and a deliberate upgrade ritual (upgrade, re-run `--all`, review the diff sheet,
re-approve goldens) rather than an incidental one.

**R13 — Valley One turns into a level-design project.** A showcase scene has no natural stopping point
and can absorb unlimited time that buys no renderer progress. *Earliest de-risk:* the layout file is
frozen at the end of M1 — topography, road, water bodies, prop and camera anchors do not change after
that; later milestones only change *materials, lighting, effects, and vegetation density*. A hard asset
budget (prop count, unique material count, vegetation instance count) is stated in the layout file and
gated on VRAM and draw calls.

**R14 — Beautiful scene, legacy truck.** The environment work will outrun the vehicle and make the truck
the worst thing in frame, which reads as "the rewrite didn't work". *Earliest de-risk:* accepted openly
in §0.5, the hero re-texture is scheduled immediately after M3, and until then money-shot framings favour
the environment.

**R15 — Solver/renderer coupling creeps back in.** RoR's solver reaches into the scene graph today,
and the port will be tempted to keep doing that. *Earliest de-risk:* the `IRenderBridge` interface in
M1 is the only seam, and a build gate greps the solver translation units for Godot and scene-graph
symbols.

---

## 7. Engineering standards

These are enforced by gates and by review, not by good intentions. Every rule here has a check, because a
standard nobody measures is a preference.

### 7.1 Structure and SOLID, applied to the parts that actually bite

SOLID matters here mostly because this project has one very high-churn area (shaders and render config)
and one very stable area (the solver), and the whole point is to keep changes in the first from touching
the second.

- **Single responsibility, enforced by file size.** One file, one job. GDScript files stay under
  **400 lines**; C++ translation units under **600**; a `.gdshader` under **300** with shared code factored
  into `.gdshaderinc` includes. Functions stay under **40 lines** and take **4 parameters or fewer** —
  past that, pass a typed object. The line limits are a proxy for responsibility, not an aesthetic: the
  gate fails the build, and the fix is always extraction, never reformatting to dodge the counter.
- **Open/closed for the render stack.** Adding an effect must not edit the pipeline. Post effects are
  `CompositorEffect` subclasses registered from a list in `post_cfg.gd`; weather is a preset dictionary;
  materials resolve through a class table. If a new effect needs the pipeline edited, that is a design
  bug to fix before shipping the effect.
- **Liskov, where it is real.** `IRenderBridge` has exactly one production implementation and one test
  double, and the test double must satisfy the same contract tests. No implementation may require callers
  to know which one they hold.
- **Interface segregation.** The solver's view of the renderer is three small interfaces — pose sink,
  height/normal query, event sink — not one fat facade. RoR's current renderer coupling is exactly what
  happens without this.
- **Dependency inversion and a one-way layer rule.** Layers: `solver` (C++, no Godot symbols) →
  `bridge` → `world`/`compat` → `harness`. Dependencies point one way only. Enforced by a gate: the
  solver translation units are grepped for Godot and scene-graph symbols, and GDScript layers are checked
  for upward imports. This is R15's mitigation, mechanised.
- **No god autoload.** `Harness` is the only autoload and it owns argument parsing, the run loop, and
  capture — nothing else. Systems are nodes or plain objects owned by whoever builds them, so a test can
  build one in isolation.
- **Configuration is data, never behaviour.** `res://config/*.gd` holds typed const dictionaries and no
  logic. Any `if` inside a config file is a review rejection; the branch belongs in the system that reads
  it. This is what keeps the CLI-only workflow honest: a visual change is a data diff, reviewable as text.
- **Composition over inheritance for game objects.** Deep node inheritance chains are how Godot projects
  rot. Maximum inheritance depth of 2 below the engine class; share behaviour by composition.

### 7.2 Formatting, naming, typing

- **Formatters are not negotiable and not manual.** `gdformat` + `gdlint` for GDScript, `clang-format`
  for C++, both with a config file committed at the repo root, both run by a pre-commit hook, and both
  re-checked by a `format` gate so a bypassed hook still fails. Formatting is never a review topic.
- **Static typing everywhere in GDScript.** Typed variables, typed parameters, typed returns; `Variant`
  requires a comment justifying it. A gate fails on untyped declarations. This project cannot afford
  GDScript's dynamic-typing failure mode, because most of its bugs will be silently-wrong numbers in
  render config.
- **Naming**: `snake_case` for files, functions, variables; `PascalCase` for classes and node names;
  `SCREAMING_SNAKE` for constants; `_leading_underscore` for private. Shader uniforms mirror the config
  key that feeds them, exactly, so a config value and its uniform can be grepped together.
- **Units and spaces in names.** `distance_m`, `time_s`, `angle_deg`, `pos_world`, `pos_actor_local`.
  Mixing spaces is the most likely bug class in a bridge that converts between world, actor-local, and
  screen space every frame (§2.5), and naming is the cheapest defence available.
- **No magic numbers in shaders or systems.** Every tunable is a named uniform or a config key. A gate
  greps shaders for bare float literals outside a small allowlist.
- **Comments explain why, never what.** Every non-obvious constant carries the reasoning or the source
  (a paper, a spec, a measurement) as a comment. Gate thresholds in particular must state why that number.

### 7.3 Error handling and diagnostics

- Fail loud in development: `assert` invariants, and for the shim's parsers, return a typed result with a
  named reason rather than a silent fallback. "Loads or fails cleanly with a named reason" is a gate
  (M1), which only works if nothing swallows errors.
- One logging facility with levels and subsystem tags, writing lines that are greppable and stable —
  the harness already depends on `HARNESS_METRIC` being machine-parsable, and log format is therefore an
  interface, not a convenience.
- Never log per-frame at default level. A per-frame log line is a performance bug and a signal-to-noise
  bug at once.

---

## 8. Documentation structure

**Decision: many small documents in a tree, not one giant file, and the tree mirrors the code.** One
enormous design document is unreadable, unreviewable, and always stale in an unknown place. Structure:

```
docs/
  README.md                  # map of the docs: what lives where. The only index.
  architecture/
    overview.md              # the layer diagram and the one-way dependency rule
    bridge.md                # §2 expanded: pose flow, skinning, motion vectors
    render-pipeline.md       # pass order, colour spaces, where each effect lives
    terrain.md               # Terrain3D integration, collision bridge, shader override
    compat-shim.md           # legacy loading, conversion cache, tier promises
  decisions/
    NNNN-<slug>.md           # ADRs: one decision per file, numbered, immutable
  guides/
    harness.md               # every CLI flag, every gate, how to add one
    human-sessions.md        # how to run and record a human session
    modding.md               # the mod author's document (§5), written for outsiders
    asset-pipeline.md        # conversion tools, derivation rules, licence process
  reference/
    config-keys.md           # generated from res://config/, never hand-written
    gates.md                 # generated from the gate files: name, oracle, threshold
```

Rules:

- **Hard size cap: 400 lines per document.** Over that, split it. Same reasoning as the code cap.
- **Decisions live in ADRs, one file each, and are immutable.** Every "decision:" in this plan becomes an
  ADR with context, the decision, what was rejected and why, and consequences. Superseding an ADR means a
  new ADR that references it — never an edit, because the reason a rejected option was rejected is the
  single most valuable thing to have written down six months later.
- **Generated docs are generated.** `config-keys.md` and `gates.md` are produced by a tool from the source
  of truth and a gate fails if they are stale. Hand-maintained lists of keys are always wrong.
- **Every document states its audience in the first line** (contributor, mod author, future maintainer).
  Mixed-audience documents are why documentation goes unread.
- **A link gate.** Broken internal links and references to files that no longer exist fail the build.
- **No duplication of source-of-truth facts.** Thresholds live in the gate files, config defaults in the
  config files; documents reference them, never restate them.

---

## 9. Gate suite hygiene

A test suite that accumulates garbage stops being trusted, and an untrusted suite is worse than none —
especially here, where the suite is the agent's only sense of sight. Rules, all enforced:

- **Every gate declares its own metadata**: name, what it proves, its oracle (§3.4 — outside oracle
  preferred, golden only as fallback), its threshold and the justification for that number, its runtime
  budget, whether it needs a GPU, and an owner milestone. A gate without this metadata does not run.
- **One gate, one claim.** A gate that fails for six unrelated reasons tells you nothing. Bundling is a
  review rejection.
- **Zero tolerance for flakes.** A gate that fails intermittently is either fixed or deleted within one
  milestone — never retried, never "re-run to be sure". Retry logic is banned: it converts a real
  non-determinism bug into background noise, and this project's determinism guarantees (§3.2) are exactly
  what the suite exists to protect. A `flake_watch` job re-runs the full suite N times and any gate that
  is not bit-stable is quarantined with an issue and a deadline.
- **Runtime budget, enforced.** Whole suite under **10 minutes** on the dev Mac; any single gate under
  **60 seconds** unless explicitly marked `slow` and excluded from the default run. A slow suite gets run
  less, and a suite that gets run less is decoration.
- **Golden budget.** Goldens are capped in number and every one is justified in its gate metadata; the
  preferred move is always to replace a golden with an outside oracle or a computed invariant. A growing
  golden count is treated as technical debt and reported by the suite itself.
- **Delete redundant gates, deliberately.** When a new gate subsumes an old one, the old one goes in the
  same commit. Coverage overlap is not free: it is duplicate maintenance and duplicate runtime.
- **Artifacts are disposable and bounded.** Everything under `artifacts/` is gitignored, written per-run
  into a timestamped directory, and pruned to the last N runs by the runner itself. Only goldens,
  oracle references, and human-session notes are committed. Nothing else earns repository space.
- **The suite is code and gets reviewed like code.** Same file-size, typing, naming, and formatting rules
  as §7 — a gate file over 400 lines or full of magic numbers is exactly the kind of test code that
  eventually nobody dares change.
- **Fixtures are deterministic and shared.** Scenarios live in one place (§3.1) and are reused across
  gates; no gate builds its own ad-hoc scene. Divergent fixtures are how suites start disagreeing with
  each other about what the product does.
- **Failure output must be actionable.** A failing gate prints the measured value, the threshold, the
  artifact path, and the worst-offending image region or frame index. "FAILED" with no number is a bug in
  the gate.
- **The suite never writes its own expectations** (§0), and it never mutates the repository — a gate that
  needs to change committed state is redesigned.

---

## 10. Files this plan creates or touches

New, in the Godot project:

- `res://harness/harness.gd`, `cameras.gd`, `scenarios.gd`, `gates/*.gd`
- `res://config/render_cfg.gd`, `light_cfg.gd`, `material_cfg.gd`, `camera_cfg.gd`, `weather_cfg.gd`,
  `post_cfg.gd`
- `res://world/world_builder.gd`, `valley_one.gd`, `valley_one_layout.gd`
- `res://shaders/vehicle.gdshader`, `terrain3d_override.gdshader`, `water.gdshader`,
  `grime_splat.gdshader`, `post_display.gdshader`, `debug_*.gdshader`
- `res://post/` — `CompositorEffect` scripts: motion blur, sun shafts, heat haze
- `res://compat/` — material derivation, particle mapping, sidecar overrides, and
  `terrain3d_collision_bridge.gd` (GDScript side)
- `tools/gate.sh`, `tools/imgdiff.gd`, `tools/derive_pbr.gd`, `tools/ies_to_cookie.gd`,
  `tools/import_dem.gd`, `tools/contact_sheet.sh`
- `addons/terrain_3d/` — Terrain3D at a pinned release, unmodified
- `THIRD_PARTY.md` and `LICENSES/` — one record per third-party asset and addon
- `oracle/` — reference images and reference data from outside sources, with provenance notes
- `patches/` — empty, with a README stating the rule that anything landing here must be justified
- `docs/` — the documentation tree of §8, including `docs/decisions/` ADRs seeded from every "decision"
  in this plan
- `.gdlintrc`, `.clang-format`, `.pre-commit-config.yaml`, and the meta-gates of §7 and §9
  (`format`, `typing`, `file_size`, `layering`, `magic_numbers`, `docs_links`, `docs_stale`,
  `gate_metadata`, `flake_watch`)

In the GDExtension (C++):

- `IRenderBridge` interface and its Godot implementation
- The de-OGRE'd `Actor` / `Beam` / `FlexBody` / `FlexMeshWheel` port
- OGRE `.mesh` / `.skeleton` reader
- Render-pose ring buffer and `invalidate_history`
- AngelScript host shim

---

## 11. Verification, end to end

The whole thing is verified by one command per gate and one command for everything:

```
tools/gate.sh --all               # every gate, PASS/FAIL table, non-zero on failure,
                                  #   then the eight-money-shot sheet as the project's current state
tools/gate.sh <gate>              # one gate
tools/gate.sh <gate> --shots      # also writes the before/after contact sheet for reading
tools/gate.sh <gate> --weather X  # same gate under any time of day / weather preset
tools/gate.sh --money-shots       # just the eight showcase frames
```

Per milestone the loop is: run the gate, read the failing number, read the contact sheet or debug
visualisation PNG, change a `.gd` or `.gdshader`, re-run. No `.tscn` is ever edited by hand; the
`scene_purity` gate enforces that. Goldens are only ever updated with an explicit flag and a recorded
human approval, and wherever an outside oracle exists the gate uses it instead.

Then the milestone is **handed to the user**: `tools/play.sh` opens a real window with the milestone's
scene and weather, live ablation hotkeys, and the HUD (§3.6). The user drives it, judges it, and closes
the milestone — or does not. Anything they find is recorded, and where it is reproducible it becomes a
replay gate so it is never re-checked by hand. The agent's job is to arrive at that session with every
automated gate already green and a specific list of what to look at.
