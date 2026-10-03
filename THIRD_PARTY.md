# Third-party dependencies

Every third-party asset, addon, and library used by this project is recorded here before it is adopted.
An entry must name the source, the pinned version, the licence, the required attribution, and why the
dependency beats writing the equivalent ourselves. Adoption requires explicit approval from the project
owner first; see `docs/architecture/overview.md` for the rule.

Licences are enforced, not trusted: the `asset_licenses` gate fails the build if any asset or addon file
has no corresponding record under `LICENSES/`.

## Adopted

### Rigs of Rods
- Source: https://github.com/RigsOfRods/rigs-of-rods
- Location: `vendor/rigs-of-rods` (git submodule, shallow)
- Pin: commit `e81b37c`
- Licence: **GPL-3.0-or-later**
- Why: the softbody solver is the reason this project exists. It is wrapped as a GDExtension rather
  than reimplemented, so fifteen years of tuned node/beam behaviour is preserved.
- Consequence: this project links GPL-3.0 code and is therefore GPL-3.0-or-later itself. Every
  dependency added from here on must be GPL-3.0-compatible.

### Rigs of Rods recipe
- Source: https://github.com/htdguide/rigs-of-rods-recipe
- Location: `vendor/rigs-of-rods-recipe` (git submodule, shallow)
- Pin: commit `57f24bf`
- Licence: see the upstream repository; used as reference documentation only, never
  linked or shipped.
- Why: 342 markdown twins of the Rigs of Rods sources, explaining each file in prose and
  pseudocode, with a SYSTEM-REQUIREMENTS document naming the external seams (renderer,
  GUI, audio, scripting, sockets) and the 2 kHz soft-body floor. The flex and physics
  directories alone carry 35 twins, which is exactly the map needed to separate the
  solver from OGRE.
- Cost if dropped: none technically; it is documentation.

### Terrain3D
- Source: https://github.com/TokisanGames/Terrain3D (asset library #3892)
- Location: `vendor/terrain3d` (git submodule, shallow), built into `game/addons/terrain_3d`
- Pin: tag `v1.0.2-stable`, commit `0077405b52e353c5e5dc3a094e7ede49833ba6fe`
- Licence: **MIT** — `LICENSES/terrain3d-v1.0.2-stable-MIT.txt`
- Attribution: Copyright (c) 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.
- Approved: 2026-09-26, by the project owner, per `docs/PLAN.md` §0 and §0.6.
- Why: it is the terrain engine, not a demo map — a C++ GDExtension clipmap terrain with a
  splat texture array and an instancer for vegetation. That is the same architecture this
  plan had already chosen, so writing it ourselves buys nothing but bugs, and it removes
  the clipmap mesh, LOD ring logic, splat scheme and scattering system M8 had budgeted.
  Being C++ it also spends no GDScript time per frame.
- Compatibility: `terrain.gdextension` declares `compatibility_minimum = 4.4` and the
  project runs Godot 4.7. GDExtension is forward compatible, which is the same argument
  that lets our own bridge build against godot-cpp 4.5 and load on 4.7.
- Built, not vendored: the published release carries binaries for eight platforms, 41 MB of
  which this macOS-only project does not run, and `.gitignore` would exclude the binaries
  anyway and leave a checkout that looks complete and does not load. `tools/build_terrain3d.sh`
  builds it from the pinned submodule instead, exactly as our own GDExtension is built.
- Collision mode is `Disabled`: Rigs of Rods' own collision stays authoritative and Godot
  physics never touches the terrain. Height and normal queries come from
  `Terrain3DData.get_height` / `get_normal` and direct region image access, which needs no
  physics and is what the height-query bridge exposes to the solver.
- Cost if dropped: the clipmap and the instancer, roughly the work M8 originally budgeted.
  The collision bridge and the shader override are ours and portable.

### godot-cpp
- Source: https://github.com/godotengine/godot-cpp
- Location: `vendor/godot-cpp` (git submodule, branch 4.5)
- Pin: commit `27d9dd23c838`
- Licence: MIT
- Why: the official GDExtension C++ bindings. Required by the chosen approach of wrapping
  the existing Rigs of Rods solver rather than reimplementing it.
- Note: pinned at 4.5 while the engine is 4.7. GDExtension is forward compatible, so
  building against the older API and declaring it as the compatibility minimum keeps the
  binary loadable on both, which is what the upstream project recommends.

### Rigs of Rods content pack
- Source: https://github.com/RigsOfRods/content (submodule of the Rigs of Rods repository)
- Location: `vendor/rigs-of-rods/content`
- Licence: see that repository's LICENSE
- Why: supplies real vehicles and a terrain from upstream, so gates can be checked
  against upstream's own published data instead of expectations written here. Both of its
  vehicles use the `submesh` path, which is how ADR 0003 came to be written.

### Chevrolet S10 pack (hero asset, not redistributed)
- Local path: `assets/mods/ChevyS1023` — **gitignored, never committed**
- Source: Rigs of Rods repository, supplied by the project owner
- Author: **Gabester** (`author chassis` and `author texture` rows in `S10offroad.truck`)
- Licence: none stated. Its `readme.txt` says, in full: "1985 Chevrolet S10 for Rigs of Rods /
  by Gabester / DO NOT modify this or use any part of it and release without my permission."
  That is an explicit restriction rather than silence: the pack may be used locally, and
  releasing it or anything built from it — including inside a web build's `.pck` — needs the
  author's permission first. **Not cleared for publication.**
- Why this one: `S10offroad.truck` has 255 nodes and uses `flexbodies` with external
  OGRE meshes, `managedmaterials` with inline material definitions, and `submesh`/`cab`
  sections. It therefore exercises both deformation paths of ADR 0003 and the legacy
  material classification of ADR 0001, which upstream's own content pack cannot.
- Consequence: gates that need it must skip cleanly when it is absent, so a fresh clone
  still runs the suite green.

### Rigs of Rods base resources (meshes, materials and textures the game itself ships)
- Location: `vendor/rigs-of-rods/resources` — part of the pinned Rigs of Rods submodule above
- Licence: **GPL-3.0-or-later**, as the rest of that repository
- Why: Rigs of Rods resolves content by name through Ogre's resource groups, so a mod may say
  `seat.mesh` or ask for the material `tracks/master` without shipping either — the game's own
  copy is found. Reading only the folder a mod was unpacked into left 56 named meshes unresolved
  across this checkout's packs and 48 object surfaces untextured. These directories are now
  searched after the mod's own, which is what upstream does.
- Attribution: already carried by the Rigs of Rods entry above; any build that ships these must
  credit the project and remain GPL-3.0-or-later.

### Rigs of Rods base content (shipped default map and vehicles)
- Local path: `vendor/rigs-of-rods/content` — a submodule of the `rigs-of-rods` submodule
- Source: https://github.com/RigsOfRods/content, pinned at `34fefdd`
- Licence: **GPL-3.0-or-later**, `vendor/rigs-of-rods/content/LICENSE`. Same licence as this
  project, so unlike the mods below it may be redistributed.
- Authors: the default map `simple2` states `terrain = tdev`, `texture = Miura`,
  `update = CuriousMike` in each of its three `.terrn2`.
- What is used: `simple2-terrain/`, which is the map Rigs of Rods itself opens with — three
  terrains over one set of files (`simple2` gravel, `simple2_a` asphalt, `simple2_w` flooded),
  1024 m, `Flat=1`. It is the default world of `tools/play.sh --truck` and the subject of
  `a_shipped_map_drives_from_a_fresh_clone`.
- Why this one: it is the only terrain this project can rely on being present. `assets/terrains/`
  and `assets/mods/` are gitignored, so before this every terrain gate skipped on a fresh clone
  and the only world the suite could build was one this project generated for itself.
- Attribution: any build shipping it must credit tdev, Miura and CuriousMike, and the Rigs of
  Rods project.

### La Paz terrain (loaded terrain, not redistributed)
- Local path: `assets/terrains/lapaz2` — **gitignored, never committed**
- Source: Rigs of Rods repository, supplied by the project owner
- Authors: as its own `lapaz.terrn2` states — `terrain = -1`, `converting = Klink`. The original
  terrain author is not named in the package; the conversion is Klink's.
- Licence: none stated. No licence file ships with the package.
- Why this one: it is a whole shipped terrain — heightmap, traction map, ground models, splat
  textures, 101 objects and two vegetation layers — so every reader in `compat/` is checked
  against a real author's data rather than against this project's own generator.
- Attribution: any build that ships it must credit La Paz and Klink on its own credits page,
  and the Rigs of Rods project for the formats and the physics.

### CIE daylight locus (reference data, no files)
- Local path: `harness/reference/daylight_locus.gd` — the formula and the published
  chromaticities, transcribed into source
- Source: Wikipedia, *Standard illuminant*, https://en.wikipedia.org/wiki/Standard_illuminant —
  the "Illuminant series D" section, which gives the CIE cubic for x as a function of correlated
  colour temperature, the quadratic for y, the 1.4388/1.4380 correction from a series name to its
  temperature, and the tabulated chromaticities of D50, D55, D65 and D75 for the 2 degree
  observer. Retrieved 2026-10-03.
- Upstream source the article cites: CIE, *Colorimetry*, 15:2004, and Wyszecki & Stiles, *Color
  Science* (2nd ed., Wiley 1982).
- Licence: the text is CC BY-SA 4.0; the chromaticities and the formula are measured and
  published constants rather than creative work, and only those are used here.
- Why it is here: Godot converts a colour temperature along the Planckian locus and sRGB's white
  point is on the daylight locus, so no `light_temperature` in this project is neutral. Catching
  a tinted light needs an illuminant colour that comes from somewhere other than this project,
  which `the_daylight_locus_is_where_the_books_put_it` holds the transcription to.

### ColorChecker reference colorimetry (reference data, no files)
- Local path: `harness/reference/colorchecker.gd` — the numbers, transcribed into source
- Source: Wikipedia, *ColorChecker*, https://en.wikipedia.org/wiki/ColorChecker — the table
  captioned "Table from Field (1990); CIE data for Illuminant C from Poynton (2008)". Retrieved
  2026-10-01 via `Special:Export`, so the retrieval is reproducible and dated.
- Upstream sources the table cites: Gary G. Field, *Color Scanning and Imaging Systems* (Graphic
  Arts Technical Foundation, 1990, ISBN 0-88362-120-7); Poynton (2008) for the CIE data under
  Illuminant C; the patch colours as described by McCamy et al. (1976). The manufacturer's sRGB
  column cites X-Rite's own `ColorData-1p_EN.pdf`.
- Licence: Wikipedia text is **CC BY-SA 4.0**. Attribution is this entry. The underlying
  measurements are published colorimetric facts rather than a creative work, and no file from any
  of these sources is redistributed — only 24 chromaticity triples, typed into a source file.
- Why this and not our own values: a gate may not write its own expectation, and colour is the
  easiest place in a renderer to break that rule. Published values are widely quoted, so quoting
  them from memory would feel like sourcing them while in fact being a self-written expectation
  with a citation stapled on. These were retrieved verbatim from one stated table.
- Also recorded: the sRGB primaries and white point (IEC 61966-2-1) from Wikipedia's *sRGB*
  article, same licence and same retrieval date, used in `harness/colorimetry.gd` to **derive**
  the RGB-to-XYZ matrix rather than transcribe it — nine numbers are easy to get subtly wrong
  and impossible to notice; eight chromaticities can be checked against the standard at a glance.

## Rejected

- Unreal Engine marketplace and Quixel/Megascans content. Licensed for use in Unreal Engine only. The
  restriction survives format conversion, so this content cannot enter the project in any form.
