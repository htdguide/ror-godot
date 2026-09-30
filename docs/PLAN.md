# Rigs of Rods → Godot 4.x: an alternative client

## Context

**Re-scoped 2026-09-30, from a rendering rewrite to a client.** What this project builds is an
alternative Rigs of Rods client: it loads the content the community already has, plays the way the
game already plays, and eventually talks to the servers and the repository the community already
uses. The renderer rewrite is the reason it is worth doing and it is now one subsystem of it rather
than the whole of it. Everything the plan said about rendering still holds; what changed is that it
is no longer the definition of done.

Rigs of Rods renders on OGRE 1.x. That renderer is the bottleneck on how the game looks, not the
simulation: no PBR, no HDR pipeline or tonemapper, no GI or AO, weak PSSM shadows, no modern AA or
upscaler, no SSR, sprite particles, 2010-era terrain and vegetation, and single-threaded draw
submission that is draw-call-bound long before the GPU is busy. The softbody solver is the part of
RoR that is actually good and is not the problem.

So: keep the simulation, replace the renderer, and build the rest of the client around it. Godot
4.x becomes the shell — windowing, scene graph, renderer, asset loading, UI, networking — and RoR's
node/beam solver comes along as a C++ GDExtension. Godot's physics engine is not used for vehicle
simulation at all.

### What "an alternative client" commits this project to

Named here so none of it is discovered late. Each has its own milestone below.

- **Every vehicle.** All of the rig-def format, not the parts one hero truck happens to use.
  Ground types first and completely; airplanes and boats are two further physics subsystems —
  aerofoils, turbojets, turboprops, screwprops, wings, autopilot, buoyancy — and they come after.
- **Every map.** `.terrn2` and legacy `.terrn`, with the features a terrain can declare that are
  read and ignored today: procedural roads, water, sky, hand-placed collision meshes, vegetation
  colour maps and sway.
- **AngelScript.** Terrains and rigs ship `.as` scripts. A scripted map loads today and then does
  nothing, with no error. AngelScript is zlib-licensed, so the real library can be bound rather
  than reimplemented.
- **Audio.** `soundsources`, per-rig sound scripts, Doppler. There is none at all today.
- **A GUI.** RoR's own is MyGUI plus ImGui: main menu, vehicle selector, repository browser, chat,
  console, top menubar. None of it exists here. Recognisably RoR and refreshed, with the
  instruments under glass — §0.11.
- **Client surface that is not the renderer.** Spawn manager, camera modes including cinecam,
  character and walking mode, save and replay, free-cam.
- **The online repository**, including upload. Second to last, and see §0.9 for why it is handled
  differently from everything else in this plan.
- **Multiplayer**, wire-compatible with RoRnet so this client joins the community's existing
  servers. Last, and §0.10 states the seam.

Things a client needs that are easy to leave out of a plan until they block it, named here for the
same reason:

- **Input, remapping and force feedback.** RoR has an input-map system with joystick, wheel and
  pedal support and FFB. This is a driving game; a wheel is not a nice-to-have, and Godot's input
  layer does not give FFB for free. Currently there is a hardcoded keyboard map and nothing else.
- **Settings persistence.** The equivalent of `RoR.cfg`: graphics, audio, input and gameplay
  settings that survive a restart. Today every tunable is a `.gd` const, which is right for gates
  and wrong for a person.
- **Skins and dashboards.** `.skin` files retexture a rig without modifying it, and `.dashboard`
  files define instrument layouts. Both are content the archive is full of and neither is read.
- **Content management at archive scale.** Upstream has a ContentManager and a cache because a user
  with 500 mods cannot pay a filesystem scan per launch. This project mounts one mod directory.
- **Character and walking mode**, which is also how a player gets into a vehicle.
- **Save and replay.**
- **Localization.** Upstream ships translations; every string this project writes is English in a
  format string today.
- **Screenshot and video capture** as user features, not as the gate harness's `--write-movie`.
- **A server browser** against the master server list, which belongs with C5.

**Local first.** The order in §1 does everything that works on one machine with no network before
either of the two networked milestones. A client that is good offline is a client worth connecting;
the reverse is not true, and a network dependency in the middle of the plan makes every milestone
after it harder to gate.

Development is CLI-only through the ClaudeGodot editor, with no human eyes in the loop by default.
That constraint drove two structural decisions that come before any other work: everything tunable
lives in `.gd` / `.gdshader` (never in a `.tscn`), and a screenshot/metrics harness was commit #1 so
the agent can see what it is doing. **The harness is now being replaced by the dev environment in
§0.8**, for the same reason and with the same authority: one window, one gate at a time, each in its
own container, and a console both the user and the agent drive.

### Decisions already fixed (from grilling, 2026-09-25)

| Question | Decision |
| --- | --- |
| Solver integration | C++ GDExtension wrapping the existing RoR beam solver. No reimplementation. |
| Engine fork | Stock Godot first. Fork only where proven impossible, patch set kept minimal and listed. |
| Legacy content | Runtime compatibility shim: existing `.truck` / `.zip` / OGRE assets load unmodified. |
| Target | **Superseded 2026-09-30.** Was: tech demo, one hero vehicle, one terrain, no multiplayer/UI/game-mode work. Now: an alternative client with full vehicle and map support, a GUI, audio, the online repository and RoRnet multiplayer. Local milestones first; the two networked ones last. |
| Platform | **macOS only for now.** The dev Mac is the sole authority for pixels, timings, and logic gates. No Linux/`xvfb`/lavapipe lane — deferred for speed, kept cheap to add later via the portability rules in §3.5. |
| Hero asset | An existing community truck with its original diffuse-only textures, unchanged. |
| Frame budget | 1080p, 60 fps, one truck + terrain. |
| Folder layout | **Mirrors upstream's `source/main/` literally**, so an RoR developer opening this project finds the file they expect. `project.godot` moves to the repo root to make that possible. Spec in §0.7. |
| Dev environment | **One window, one gate at a time, each in its own container**, driven by a Quake/Counter-Strike-style console that both the user and the agent use. Replaces the one-window-per-gate runner. Spec in §0.8. |
| Netcode | **RoRnet first, behind an `ITransport` seam**, so this client joins existing servers and a native protocol can be added later without the simulation knowing. Spec in §0.10. |
| Showcase scene | A Rigs of Rods terrain loaded from the files its author shipped, standing up from M1 and dressed progressively by every later milestone. Spec in §0.5 — which supersedes the generated "Valley One" that section originally asked for. |
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

## 0.5 The showcase scene — a terrain its author shipped

**Superseded 2026-09-30.** This section asked for "Valley One": a 2 x 2 km valley assembled from
free assets over a public-domain heightmap, generated by this project's own code from a
declarative layout, with a switchback road, a ford, a washout, a rock shelf, a lake, a tunnel and
a conifer stand placed in it. It was built and it worked. It is removed, and the showcase scene is
now a Rigs of Rods terrain loaded from the files its author shipped.

**Why it was removed.** A world this project generates is a world whose gates are this project
agreeing with itself. Valley One's features were placed by the same code that then measured them,
so the three drivability gates PLAN M1 acceptance 7 asked for — `switchback_climb`,
`ford_crossing`, `rut_traverse` — proved that the generator and the solver agreed about a road the
generator had drawn. A fault in the compatibility readers, which is the part of this project that
can actually be wrong, could not reach any of them. The same was true of the flat test park.
Meanwhile every gate that stood on an author's terrain skipped on a fresh clone, because the
terrains and the hero vehicle are gitignored for licensing reasons, so the suite's only reliable
world was the one it could not learn anything from.

### What the showcase is now

- **Rigs of Rods' own default map**, `vendor/rigs-of-rods/content/simple2-terrain`, is the world
  that is always present: a pinned GPL submodule holding the three terrains the game itself opens
  with. 1024 m, `Flat=1`, gravel or asphalt or flooded. It is what `tools/play.sh --truck` opens
  with no arguments and it is the subject of `a_shipped_map_drives_from_a_fresh_clone`.
- **La Paz** is the terrain with relief, imagery and objects on it: a whole shipped package —
  heightmap, traction map, ground models, splat textures, 101 objects, two vegetation layers — and
  the subject of the gates that need a real map. Imported locally with
  `tools/import_terrain.sh`; gates that need it skip cleanly when it is absent.
- **Any Rigs of Rods terrain** can be the showcase, which is the point: `tools/import_terrain.sh`
  puts one in the library and `tools/play.sh --truck --map <name>` drives it.

### What this costs, stated plainly

Three things the generated valley provided are now gone, and they are gone rather than replaced:

- **Features on demand.** A ford, a switchback at a stated grade, a rut field and an off-camber
  shelf were placed to order at known coordinates with known numbers. A shipped terrain has
  whatever its author drew, and finding a feature on it is a search rather than a lookup. The
  gates that need ground of a particular shape now search for it — `rig_settles_on_terrain` looks
  for a slope, `terrain_takes_the_light` looks for a level patch,
  `a_route_across_a_shipped_terrain_completes` looks for a drivable heading — and each reports
  where it went.
- **Water.** Valley One had a lake and a river derived from the valley floor, with four gates on
  them. A terrain's `Water` and `WaterLine` are read and ignored, so there is no water in the
  project at all until that is implemented. `simple2_w` declares water at 100 m and renders dry.
- **The M2 staging that ran through the valley.** Vegetation tiers, the fog bank, the tunnel as a
  GI subject and the atmosphere volume were staged against features this project placed. They now
  have to come from a terrain's own files, which is a larger job than dressing a scene: it is
  reading `.tobj` procedural roads, vegetation colour maps and sway, and a terrain's water.

### The money shots

A fixed set of frames that every visual milestone re-renders, so progress is legible as one
before/after sheet. The eight named here previously — `valley_vista`, `switchback_backlit`,
`ford_crossing`, `tunnel_headlights`, `rock_traverse`, `lake_dusk`, `rain_road`,
`wheel_macro_mud` — named features of the deleted valley and half of them have no subject any
more. **Re-deriving them from a shipped terrain is open work and nothing renders the sheet
today.** `ror_terrain_photoset` renders La Paz and `park_photoset`/`valley_photoset` are gone.

What a replacement set has to satisfy, so it is not the same mistake again: each frame is placed
from a feature the *terrain* declares — its own spawn, its own objects, its own surfaces — or
from a search over its own heightmap, never from a coordinate written down beside it.

### Where the assets come from, and the licence trap

Still binding, and the reason the showcase is what it is:

- Almost every high-fidelity ready-made map is unusable here. Epic's free Megascans/Quixel and
  marketplace environments are licensed **for use in Unreal Engine only** — they cannot ship in a
  Godot project, and that restriction survives conversion. BeamNG, Assetto Corsa and similar maps
  are proprietary. This is the trap to avoid before anyone starts converting anything.
- The Rigs of Rods archive's own terrains load through the shim, which is what the project now
  stands on. They are the 2010-era look the rewrite exists to escape (see R10), and that is a
  reason to improve the renderer rather than a reason to generate a scene: the renderer is what is
  being rewritten, and it has to be judged on content it will actually be given.
- Base Rigs of Rods content is GPL-3.0, the same licence as this project, so it may be
  redistributed. Community mods generally state no licence at all and cannot be — the hero
  vehicle's own readme forbids it explicitly. See `THIRD_PARTY.md`.

Sourcing tiers for the assets a milestone still needs — materials, HDRIs, vegetation — in
preference order, each still needing the §0 approval ask before adoption:
1. **Godot asset library, MIT/CC0.** Terrain3D came from there and is approved.
2. **CC0 libraries** — PBR ground/rock/bark materials and HDRIs from Poly Haven and ambientCG;
   CC0 vegetation and prop kits.
3. **CC-BY** — higher-end environment sets from open-movie/production sources, with attribution.

**Licence hygiene is a gate, not a promise.** Every submodule and shipped addon lands with a
`LICENSES/` record and a `THIRD_PARTY.md` entry naming source, author, licence and reason. The
`asset_licenses` gate fails the build otherwise, and rejects Unreal-locked content by name.

### Structure, given the CLI-only rule

A world is built by `res://world/terrain_world.gd` from a `RorTerrain` — an author's own files,
read by `res://world/ror_terrain.gd` and `res://compat/`. There is no scene file and no layout
file: a terrain is data somebody else wrote, so there is nothing here to place by hand and nothing
to keep diffable that is not already a text diff of the readers.

Weather and time of day are **presets**, each a const dictionary in `res://config/weather_cfg.gd`
combining sun angle and colour, sky, fog and volumetric settings, cloud choice, wetness level and
particle activity: `dawn_mist`, `noon_clear`, `overcast`, `golden_dusk`, `night_clear`,
`rain_storm`, `fog_bank`. A preset name is a CLI argument, so any gate can be run under any
weather.

### Staging: the renderer is never blocked on a late milestone

- **M1** — terrains load from their authors' files, with collision, objects and vegetation;
  legacy-equivalent materials. Ugly, drivable, complete.
- **M2** — PBR ground and rock materials, HDRI sky per weather preset, vegetation tier 1, fog.
  This is the milestone where it first looks good.
- **M4/M5** — GI, shadow overhaul, night and dusk presets, volumetric shafts.
- **M6** — SSR on the road, rain wetness, terrain decals (puddles, ruts, tyre marks).
- **M7** — dust, spray, tyre smoke, rain particles; vegetation tiers 2 and 3.
- **M8** — FFT water; terrain texel density raised.

**Water is now unscheduled rather than staged.** The plan previously put a reflective,
depth-faded plane in M2 and the FFT solver in M8, behind one material interface and one
water-height query. That seam is still the right one, but a terrain's own `Water` and `WaterLine`
have to be read first, and nothing does that yet.

### A consequence to state plainly

A beautiful environment beside an untouched diffuse-only truck will make the truck the ugliest
thing in frame. That contrast is the strongest argument for moving the hero-asset re-texture up,
and it is scheduled immediately after M3 for that reason (see R10).


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

## 0.7 Folder layout — mirror upstream's own tree

**Decision: `game/` mirrors `source/main/` from the Rigs of Rods repository, directory for
directory.** The reason is people, not code. This project asks RoR developers to look at a Godot
codebase and recognise their own game in it, and a tree named after this project's own history —
`compat/`, `world/` — maps to nothing they know. `resources/` and `terrain/` do.

```
project.godot            <- at the REPO ROOT, not in game/
game/
  physics/               solver glue, ground models, heightfield     (source/main/physics)
  gfx/                   materials, flexbodies, props, flares, sky   (source/main/gfx)
  terrain/               terrain reading, objects, vegetation        (source/main/terrain)
  resources/             rig-def, .otc, .terrn2, .odef, OGRE mesh    (source/main/resources)
  shaders/               shared by every layer that draws
  config/                the game's own tunables, as `.gd` consts
  gui/                   menu, vehicle selector, chat, menubar       (source/main/gui)
  network/               RoRnet, ITransport                          (source/main/network)
  audio/                 sound sources, engine sound                 (source/main/audio)
  scripting/             AngelScript binding                         (source/main/scripting)
  utils/                 shared helpers                              (source/main/utils)
harness/                 THIS PROJECT'S OWN — upstream has no counterpart
  gates/                 one file per gate
  console/               the dev console and its command surface
  dev/                   the one-window runner, containers, probes
addons/                  Terrain3D — Godot requires this at the project root
bin/                     the GDExtension and its .gdextension
extension/src/           mirrors game/'s division
tools/                   shell entry points                          (upstream tools/)
docs/                    this project's own documents
```

Two things in this layout are corrections to the first draft of it, both forced by building it:

- **`config/` is under `game/`, not under `harness/`.** Shipping code must not depend on the test
  harness, and every one of these is a tunable of the game rather than of the gates. C1's settings
  persistence is what they become for a user.
- **`shaders/` is under `game/`, beside `gfx/` rather than inside it.** A shader is an asset that
  any layer which draws may use, the way config is: with them under `gfx/`, `game/terrain/`
  referencing the foliage shader read as terrain depending on gfx and the `layering` gate said so.
  Upstream keeps its own shader and material assets in its content tree rather than in
  `source/main`, so this is not a departure from the mirror.

**`project.godot` moves to the repo root.** Godot loads resources only from its own project
directory, so a top-level `harness/` is invisible to an engine rooted at `game/`. Paths become
`res://game/...` and `res://harness/...`, and `tools/*.sh` invoke `--path .` instead of
`--path game`. This is a prerequisite of the layout decision rather than a separate choice.

**`harness/` is deliberately not given an upstream-looking name.** Upstream's `tools/` holds build
scripts; naming a test harness after it would give an RoR developer a familiar directory with an
unfamiliar meaning, which is worse than an honestly new one.

**The move is mechanical and must be provably so.** Every commit in the move keeps the suite green
and changes no behaviour: the `layering` gate already knows which directories may depend on which
and is updated in the same commit, and `file_size`, `typing` and `scene_purity` do not care where a
file lives. A rename that also changes something is two commits.

**Moving `res://` is what makes the move dangerous, and it caught two things.** `res://` was
`<repo>/game` and is now `<repo>`, so every expression of the form `res://..` silently moved up one
directory: `SourceScan.repo_root()` returned the repository's *parent*, and `Capture.artifact_root()`
wrote every artifact outside the repository. Both passed their gates while doing it, because a gate
that reads and writes under one wrong root is self-consistent. Anything computing a path from
`res://` is worth re-reading after this move rather than trusted.

**Godot imports everything under its project root**, which after the move includes `vendor/`,
`assets/`, `artifacts/` and `history/` — hundreds of megabytes of DDS, PNG and mesh files that the
engine has no business importing and that made the first import after the move never finish. Each
carries a `.gdignore`, which stops the importer and does not stop `FileAccess`: terrains and mods
are read by absolute path, so nothing about loading content depends on Godot indexing it.

---

## 0.8 The dev environment — one window, contained gates, one console

**Decision: gates run inside one long-lived window, one at a time, each in its own container, driven
by a console that both the user and the agent use.** The present runner opens a fresh OS window per
gate. With 76 gates that is 76 windows over a suite run, it is the single most annoying thing about
working here, and it is also slow: each one pays engine startup, shader compilation and Terrain3D
region loading again.

### What "containerized" has to mean

Not a process. A gate that leaks state into the next gate is worse than a gate that is slow,
because the failure it produces is order-dependent and looks like a flake. So a container is:

- **Its own `SubViewport` with its own `World3D`.** Separate environment, separate lighting,
  separate physics space, separate camera. Nothing a gate adds to its world can be seen by the next.
- **Torn down and asserted empty.** After each gate the container is freed and the node count,
  the `RenderingServer` instance count and the orphan-node count are checked back to their
  pre-gate values. A leak fails the gate that caused it, not the one that ran next.
- **Its own static state.** This is the part that needs work rather than a viewport:
  `TerrainWorld._shape` and `_surfaces`, `BlockoutWorld._clouds` and every other `static var` in
  the tree is process-global and survives a container. Each of them is either reset by the
  container or moved into an instance the container owns. **`static var` becomes a lint**, the way
  `no_global_random` already is, because this is exactly the class of bug the containers exist to
  remove.
- **Reproducible in isolation.** `gate run <name>` in a fresh window and `gate run <name>` as the
  fortieth gate of a suite run must produce the same number. A gate whose result depends on what
  ran before it is a broken gate and the runner proves this by running the suite in a second,
  seeded order and comparing. **This is the acceptance test for the whole dev environment** — it
  is also the only way to know the containers work, since "it looked fine" is not available.

### The console

A Quake/Counter-Strike-style drop-down console, because that is the interaction RoR developers and
players already know, and because it is the one UI that is useful before any other UI exists.

- **Opens on `` ` `` / F1**, over whatever is running, without pausing it unless asked.
- **Commands and cvars.** `gate run <name>`, `gate list`, `gate all`, `gate why <name>`,
  `map load <name>`, `veh spawn <path>`, `weather <preset>`, `cam <mode>`, `r_*` render cvars,
  `sim_*` solver cvars. A cvar reads and writes the same `harness/config/*.gd` values the gates
  use, so a number tuned in the console is the number a gate then measures.
- **Autocomplete, history, aliases.** Tab completes commands, cvar names, gate names, map names and
  vehicle paths from the library. Up/down history persisted across runs. `alias` and `bind`.
- **Output is scrollable, filterable and copyable**, with severity colours and a `condump`.
- **It is the only command surface.** The agent's channel, the keyboard and `tools/gate.sh` all
  dispatch into the same command table, so anything the user can type, the agent can run, and
  neither has a capability the other lacks.

### The agent channel

**Decision: a watched file drop is the contract, with a local socket as a fast path.** Both front
ends dispatch into the same command table as the keyboard.

```
artifacts/console/in/<seq>.cmd     the agent writes; one command or a script per file
artifacts/console/out.jsonl        the console appends exactly one line per command
artifacts/console/state.json       current cvars, loaded map, spawned rigs, last N errors
127.0.0.1:<port>                   same commands, line protocol, when a window is up
```

**Token efficiency is a design constraint, not a nicety**, since the agent pays for every line it
reads:

- One JSON line per command, with `seq` so the agent reads only what it asked for.
- `ok`, `ms`, and a `detail` string that is the gate's own one-line result — never a frame, never
  a log dump, never a stack unless it failed.
- Anything large — an image, a capture, a heightfield — is written to a file and the line carries
  the **path**, not the content.
- `--quiet` by default: engine chatter, Terrain3D's region logging and Godot's own warnings go to a
  file, not to the channel. Today a single gate run prints region-save lines the agent has to read
  past to find one result.
- A script file is one round trip for many commands, so a whole investigation costs one write and
  one read rather than one per step.

### What survives from the old harness

`tools/gate.sh` stays, because CI and a headless machine need a runner that is not a window, and
because a gate must be runnable when the console itself is what is broken. It becomes a thin client
of the same command table. The gate metadata contract, the gate graph and `--all --every` are
unchanged.

---

## 0.9 The online repository — why it is handled differently

Second to last in the order, and the only milestone in this plan that writes to a service other
people depend on. Upload, edit and delete of the user's own content are in scope, and that means a
bug here does not produce a wrong pixel, it produces wrong content published under the user's name
on a live community site.

Rules, fixed now rather than at implementation time:

- **Every write is confirmed by the user, per action, with what will be sent shown first.** No
  batch upload that was not reviewed item by item.
- **A dry-run mode that exercises the whole path and sends nothing** is part of the milestone, not
  an afterthought, and it is what the gates use. **No gate ever writes to the live repository.**
- **Credentials live in the OS keychain.** Never in the repo, never in a log, never in a gate
  artifact, never in the console's `condump` or the agent's channel.
- **Nothing is mirrored or re-hosted.** The user downloads their own copy; this client never becomes
  a distribution point for content whose licence does not allow it — which is most of the archive.
  See `THIRD_PARTY.md`.
- **An open question to settle before any code**: the repository is a forum resource manager and its
  write API is not a documented public interface. Whether a third-party client may upload through it
  at all is a question for the Rigs of Rods maintainers, not one to answer by reading the network
  traffic. Read-only browse and download are uncontroversial; upload is not, and it may end up out
  of scope for reasons that have nothing to do with engineering.

---

## 0.10 Multiplayer — the transport seam

Last, and structurally simple as long as one decision is honoured: **the simulation never learns
which transport it is on.**

```
game/network/
  i_transport.gd / .h      connect, disconnect, register stream, send, poll
  rornet_transport         RoRnet as upstream defines it. First and primary.
  native_transport         later, optional
```

- **RoRnet is a wire contract, not an interface to design.** `source/main/network/RoRnet.h` defines
  fixed-size structs and a version string, and the server's handshake rejects a client whose version
  does not match. That version is pinned from the submodule, so a submodule bump that changes it is
  a change this project has to notice.
- **It is state replication, not lockstep.** RoRnet registers a stream per actor and sends node
  state; it does not send inputs and it does not require two clients to compute the same result.
  That is the reason multiplayer does not depend on solver determinism, and it is why this milestone
  can come after the solver's own divergence question rather than before it.
- **The outside oracle is a live server with other clients on it**, which is the strongest oracle
  in this entire plan and the reason RoRnet comes before any native protocol. A native transport
  with no players has no oracle at all.
- **Real RoR clients on the same server are the fidelity check**: if this client's actor looks and
  moves right in their windows, the streams are right.

---


## 0.11 UI design — Rigs of Rods, refreshed, and the instruments under glass

**Decision: the UI is recognisably Rigs of Rods and redrawn, not redesigned.** The same wallpapers,
the same main-menu furniture, the same layout a player already knows how to use — a player who has
used RoR should never have to look for anything. What changes is the drawing: current type, real
spacing, a modern skin. The same rule as §0.7's folder mirror, applied to what the user sees rather
than to what a developer reads.

### The instruments are under glass

The distinguishing idea, and it applies to every ported RoR gauge: a speedometer stays *that*
speedometer, the same dial and the same needle, wrapped in a piece of glass that behaves like glass.
Three behaviours, and each is a separate thing to get right:

- **It reflects its environment.** A specular layer over the dial taking the scene's own reflection
  probe — the actor already has one — so the glass picks up the sky, the cab and what is out of the
  window. Subtle: a reflection that competes with the needle is a worse instrument.
- **It lights from below when the lights are on.** A warm glow rising from the bottom edge, the way
  a Casio watch backlight does, driven by the same lamp state `lights_follow_the_controls` already
  gates. Off when the lights are off — the lamp work established that an unshaded material draws
  its albedo and ignores emission, so this is an emissive layer and not a brighter texture.
- **It has inertia tied to the vehicle.** The glass, and the housing it sits in, move slightly
  against the vehicle's own acceleration — a gyroscope mounted in the cab, not a camera shake. The
  reference is Night Runners. The input is the solver's own acceleration, which the cockpit already
  reads, so this is a damped spring on a transform and not a new source of truth.

**Why this is stated in the plan rather than left to implementation.** It is the project's one
visual signature, it applies to every gauge rather than to one screen, and all three behaviours are
measurable — which means they are gateable, and a thing that looks right in a screenshot and is
wrong in motion is exactly what this project's gates exist to catch:

- The reflection changes when the environment changes, and does not when it does not.
- The backlight's luminance follows the lamp state, and the gauge is readable in both states — the
  failure mode is a dial that is beautiful at night and unreadable at noon.
- The inertia is bounded and settles: a gauge that keeps swinging after the vehicle is still, or
  that swings far enough to be read wrong, fails. A number for how far it may move and how quickly
  it must settle, not an opinion.

**The needle is not the glass.** The reading has to be correct and legible first;
`cockpit_tracks_the_drivetrain` already holds that the dials read the drivetrain, and no amount of
glass may cost that gate. Inertia moves the housing, never the value.

---

## 1. Milestone plan

**Re-ordered 2026-09-30 for the client scope.** Two prerequisites still come ahead of everything
because nothing renders without them, and the order after them is: the dev environment, then every
local milestone, then the two networked ones.

| # | Milestone | Why here |
| --- | --- | --- |
| M0 | CLI harness | done; nothing else could be committed before it |
| M1 | Softbody bridge + a rig on screen | done but for three acceptance items, listed in its section |
| **D0** | **The dev environment** (§0.8) | **next.** Every milestone after it is built and gated inside it, so it comes before them rather than being retrofitted. Carries the §0.7 tree mirror, because moving files is cheapest before there are more of them. |
| M2 | PBR + HDR + tonemap + IBL sky | first after D0: it is the highest visual payoff per unit work, and it closes the one red gate in the suite (`terrain_takes_the_light`, §0.5) |
| M2b | Physical camera and the post stack | follows M2 directly; same pipeline |
| C1 | GUI + audio | the point at which this stops being a harness with a window and becomes a client a person can use. Menu, vehicle selector, console surfaced to the user, chat shell, engine and impact sound. |
| C2 | Format coverage + AngelScript | every ground rig-def section and every `.terrn2` feature, plus the script interpreter. The mod archive is the oracle. |
| M3–M8 | The rest of the renderer | motion vectors, TAA, FSR, GI, AO, shadow overhaul, volumetrics, SSR, wetness, particles, FFT water, terrain VT |
| C3 | Airplanes and boats | two further physics subsystems: aerofoils, turbojets, turboprops, screwprops, wings, autopilot, buoyancy |
| C4 | The online repository (§0.9) | second to last. Networked, and the only milestone that writes to a service other people depend on. |
| C5 | Multiplayer (§0.10) | last. RoRnet behind `ITransport`; a live server with other clients on it is the oracle. |

Not yet placed in a milestone, and each needs one before it is forgotten: input remapping and force
feedback, settings persistence, skins and dashboards, content management at archive scale, character
and walking mode, save and replay, localization, user-facing capture. Input and settings are the two
that C1 will run into immediately.

**Local first, and the reason is gating.** Every milestone through C3 can be checked on one machine
against content that is already on disk. Both networked milestones depend on a service this project
does not control, and a gate that needs the internet is a gate that goes red for reasons that are
nobody's fault. Putting them last means no local milestone is ever blocked behind one.

**What the renderer milestones below still assume, and no longer should.** M3 through M8 were
written when the target was one hero vehicle on one terrain. Their acceptance criteria are still
correct as written — they are about pixels and frame times — but three of them reference the
generated valley or the eight money shots, and both are gone (§0.5). Each is marked where it comes
up. A replacement money-shot set is open work and M2 is the milestone that needs it first.

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
- **A shipped terrain, drivable** (§0.5 staging): Terrain3D installed and pinned; a terrain read
  from its author's own files — heightmap, traction map, ground models, splat textures, objects,
  vegetation — imported by `world/terrain_world.gd`, with collision mode `Disabled` and Rigs of
  Rods' collision driven through the height-query bridge (§0.6). Ugly, fully drivable.
  Superseded: this originally asked for a generated valley over a public-domain DEM with a road
  spline and ruts carved in. See §0.5 for why that is gone.

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
6. `terrain_collision_agreement`: sampled across a whole shipped terrain, off the lattice on both
   axes, the height RoR's collision sees and the height Terrain3D renders agree within a stated
   tolerance, and the surface the solver grips on is the one the author's traction map paints. A
   visual-versus-collision mismatch is the classic "wheels floating / sunk" bug and it must be a
   number, not an observation.
7. `drivability`: `a_route_across_a_shipped_terrain_completes` drives a scripted route across a
   terrain its author drew — the route derived from the terrain's own spawn and heightmap, not
   written down beside it — without the actor falling through terrain, getting stuck, or exploding;
   solver energy stays bounded. Superseded: this originally named `switchback_climb`,
   `ford_crossing` and `rut_traverse`, three features of the generated valley. See §0.5.
8. `asset_licenses` passes: every scene asset and addon has a `LICENSES/` record and a `THIRD_PARTY.md`
   entry with a version pin.

**Visual verification:** contact sheet from `--write-movie` of a 5-second drop test, eyeballed by the
agent for correct deformation silhouette; side-by-side PNG of the same frame rendered from the CPU
FlexBody path and the skinned path, plus the numeric error histogram as the real proof. The money-shot
sheet that was to establish the before-image does not exist: the eight frames named features of the
deleted valley and a replacement set is open work (§0.5).

---

### D0 — The dev environment (next; everything after it is built inside it)

Full detail in §0.8, and the tree mirror in §0.7. This is infrastructure with no user-visible
output, and it comes first because every milestone after it is gated inside it and because moving
the tree is cheapest while the tree is small.

Scope:
- **The §0.7 tree mirror**, including `project.godot` moving to the repo root. Mechanical, suite
  green at every commit, `layering` updated in the same commit as the move it describes.
- **One window, one gate at a time, each in its own `SubViewport`/`World3D` container**, torn down
  and asserted empty between gates.
- **`static var` eliminated or container-owned**, and a lint that keeps it that way. This is the
  real work of the milestone: a viewport is easy, process-global state is not.
- **The console**: command table, cvars bound to `harness/config/*.gd`, autocomplete over commands,
  cvars, gate names, maps and vehicle paths, persisted history, aliases and binds, `condump`.
- **The agent channel**: watched file drop plus a local socket, one JSONL line per command, large
  results written to files and referenced by path, engine chatter off the channel by default.
- **`tools/gate.sh` becomes a thin client of the same command table**, so CI and a broken console
  both still have a runner.

**Acceptance:**
1. `gate all` runs the whole suite in **one** window and every gate's result matches what it
   produces in a fresh window of its own, gate for gate.
2. **Order independence**: the suite run in a second, seeded order produces identical results. This
   is the gate on the containers themselves and the milestone does not close without it.
3. **No leaks**: after each gate the container is freed and node count, `RenderingServer` instance
   count and orphan-node count are back to their pre-gate values. A leak fails the gate that caused
   it.
4. A suite run is faster than the present one-window-per-gate runner, reported as a number. Engine
   startup, shader compilation and terrain import are paid once.
5. `static_state` gate: no `static var` outside `harness/config/` holds mutable state.
6. The console runs every command the agent's channel can, and the reverse, from one table — proven
   by a gate that drives the same command through both front ends and compares.
7. One command through the agent channel costs one JSONL line; a gate's failure carries its own
   detail string and an artifact path, not a log.

**Visual verification:** the user opens one window, types `gate all`, watches gates run in place,
and can stop on a failure and inspect that gate's world with the free camera without relaunching.

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
- **The scene, v2** — the milestone where it first looks good: PBR ground, rock and bark
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
a wide vista, 85 mm for a wheel macro) maps directly onto the money shots. Auto-exposure is
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

### C1 — GUI and audio (the client becomes usable)

The point at which this stops being a harness that happens to open a window. Placed after M2/M2b so
the first thing a person sees is the renderer at its best rather than at its M1 state.

Scope:
- **Main menu, vehicle selector, map selector**, reading the terrain library and the mod directory
  and showing what each one says about itself — which `RorTerrainLibrary.summaries()` already does.
- **The console surfaced to the user** as the in-game console, not a dev tool. It exists from D0;
  this is where it gets a skin, a chat pane and a menubar around it.
- **Audio, which does not exist at all today.** `soundsources` and `soundsources2` from the rig-def,
  per-rig sound scripts, engine sound driven by the drivetrain state the cockpit already reads,
  tyre and impact sound driven by `ror_ground`'s own contact events, Doppler and distance
  attenuation.
- **Camera modes** including cinecam from the rig's own `cinecam` section, and free-cam.
- **Spawn manager**: more than one actor at a time, selected, removed, reset.

**Acceptance:**
1. A person can start the client, pick a map, pick a vehicle, drive it and quit without a command
   line. Gated by a scripted UI walk, not by a screenshot.
2. `a_rig_sounds_like_its_drivetrain`: engine pitch tracks reported RPM over a sweep, measured off
   the audio bus rather than asserted.
3. Impact sound fires on the same contact events the solver reports, within one frame.
4. Two actors spawn, are independently driven, and neither's solver state reaches the other.
5. Cinecam matches the position the rig's own file declares.

**UI design is decided — see §0.11.** Recognisably Rigs of Rods, refreshed: the same wallpapers and
the same layout a player already knows, redrawn; and the in-vehicle instruments under glass.

---

### C2 — Format coverage and AngelScript (the archive is the oracle)

Every ground rig-def section and every `.terrn2` feature, plus the script interpreter. This is the
milestone the `mod_corpus` gate from M1 acceptance 5 belongs to, and it is where that gate stops
asserting "loads or fails cleanly" and starts asserting fidelity per section.

Scope, vehicles:
- **Every section a ground rig uses.** The named gaps today: `contacters` (79 rows unparsed on the
  hero truck), `commands2` not key-driven so doors do not open, differentials not modelled,
  `fusedrag` given per-node drag instead of a fuselage vector, traction control and ABS absent,
  flares placed but not animated.
- **Every ground type**: `.truck`, `.load`, `.trailer`, `.car`, `.fixed`.
- **A section inventory as a gate**: every section upstream's `RigDef::Parser` knows, against what
  this project reads, reported as a number. A section that is parsed and ignored counts as ignored.

Scope, terrains:
- **Procedural roads** from `.tobj` `road`/`road2`, which are reported as unread lines today.
- **Water**, a terrain's own `Water` and `WaterLine`. There is no water in the project at all since
  the valley went, so this is also where water returns.
- **Hand-placed collision meshes**, which a terrain can ship.
- **Vegetation colour maps and sway**, read and unused today.
- **Legacy `.terrn`**, the pre-0.38 format, if "all maps" is to mean all of them.
- **Sky**: the terrn2 names a cube map from RoR's core resources, which a terrain does not ship.

Scope, scripting:
- **Bind the real AngelScript library** — zlib licence, GPL-compatible — rather than reimplement it.
- **Upstream's script API surface**, as much of it as the archive actually uses, measured rather
  than guessed: the corpus says which functions real scripts call.
- **A script that calls something unbound fails loudly and names it**, which is the whole point.
  Today a scripted map loads and silently does nothing.

**Acceptance:**
1. `mod_corpus` over 200 archive mods: zero crashes, zero hangs, each either loads or names its
   unsupported feature. (M1 acceptance 5, unmet, lands here.)
2. `section_coverage`: the count of rig-def sections read, against upstream's parser, with the
   unread ones named individually. A number that can only go up.
3. `a_terrains_own_road_is_drivable`: a `.tobj` procedural road, driven.
4. `a_terrains_own_water_floats_a_rig`: water read from a terrain's own declaration.
5. `a_scripted_map_runs_its_script`, against a real archive map that ships one.
6. Doors open, indicators blink, brake lights follow the pedal, reversing lights follow the gear.

---

### C3 — Airplanes and boats

Two further physics subsystems, and the reason they are not in C2: they are not more parsing, they
are aerodynamics and buoyancy. Until this milestone an `.airplane` or `.boat` spawns and **says it
does not fly or float yet**, rather than silently sinking.

Scope:
- **Aerofoils** from `airfoils/*.afl`, upstream's own tables.
- **Turbojets, turboprops, screwprops**, each a port of upstream's own law, each parity-checked the
  way `ror_ground` was.
- **Wings, ailerons, elevators, rudders, autopilot.**
- **Buoyancy**, per submesh, which is also what a terrain's water from C2 feeds.

**Acceptance:** per-force-law parity against upstream extracted functions, the way
`upstream_contact_parity` works today; then an aircraft that takes off, flies level and lands, and a
boat that floats at the waterline its file implies and makes way under its own screw.

---

### C4 — The online repository

Rules in §0.9 and they are binding. Browse, search, download into the library, account login, and
upload/edit/delete of the user's own content, with per-action confirmation, a dry-run mode the gates
use, credentials in the OS keychain, and no mirroring.

**Acceptance:** browse and download gated against a recorded fixture rather than the live service;
every write path gated in dry-run only; a gate that fails if any credential appears in an artifact,
a log, a `condump` or the agent's channel. **Before any code: the answer from the Rigs of Rods
maintainers on whether a third-party client may upload at all** (§0.9).

---

### C5 — Multiplayer

Seam in §0.10. `ITransport`, then `RoRnetTransport` pinned to the submodule's own RoRnet version,
then joinability, streams, chat and the user list. A native transport is optional and later.

**Acceptance:** this client joins a real Rigs of Rods server alongside real clients; its actor
appears and moves correctly **in their windows**, which is the oracle; chat and the user list work
both ways; a version mismatch is reported as a version mismatch rather than a failure to connect.
The simulation contains no reference to any transport.

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
  (node path or a world position on the terrain), focal length, f-stop, shutter, fixed exposure,
  and which scenario and weather preset to build. Covers the eight money shots (§0.5) —
  `valley_vista`, `switchback_backlit`, `ford_crossing`, `tunnel_headlights`, `rock_traverse`,
  `lake_dusk`, `rain_road`, `wheel_macro_mud` — plus the diagnostic presets `hero_3q`, `hero_rear_low`,
  `cockpit`, `chase`, `overdraw_top`.
- `res://harness/scenarios.gd` — deterministic scripted scenarios, a fixed sequence of solver inputs
  over a fixed tick count. Only `static` exists; the driving gates use `harness/drive_route.gd` and
  `harness/drive_scenario.gd`, which follow waypoints over a terrain instead. The scenarios this
  section listed against the deleted valley — `tunnel_drive`, `switchback_climb`, `ford_crossing`,
  `rut_traverse` — are gone with it (§0.5).
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
tools/play.sh                       # the shipped default map, hero truck, last weather, windowed
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

**R13 — the showcase turns into a level-design project.** A showcase scene has no natural stopping point
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
- `res://world/terrain_world.gd`, `ror_terrain.gd`
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
