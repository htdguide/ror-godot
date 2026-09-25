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
- Licence: not stated in the package. No licence file ships with it, so no redistribution
  right can be assumed. It is used locally as a test and hero asset only.
- Why this one: `S10offroad.truck` has 255 nodes and uses `flexbodies` with external
  OGRE meshes, `managedmaterials` with inline material definitions, and `submesh`/`cab`
  sections. It therefore exercises both deformation paths of ADR 0003 and the legacy
  material classification of ADR 0001, which upstream's own content pack cannot.
- Consequence: gates that need it must skip cleanly when it is absent, so a fresh clone
  still runs the suite green.

## Rejected

- Unreal Engine marketplace and Quixel/Megascans content. Licensed for use in Unreal Engine only. The
  restriction survives format conversion, so this content cannot enter the project in any form.
