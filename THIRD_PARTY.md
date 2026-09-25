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
- Licence: see the upstream repository; used as reference documentation only, never
  linked or shipped.
- Why: 342 markdown twins of the Rigs of Rods sources, explaining each file in prose and
  pseudocode, with a SYSTEM-REQUIREMENTS document naming the external seams (renderer,
  GUI, audio, scripting, sockets) and the 2 kHz soft-body floor. The flex and physics
  directories alone carry 35 twins, which is exactly the map needed to separate the
  solver from OGRE.
- Cost if dropped: none technically; it is documentation.

### godot-cpp
- Source: https://github.com/godotengine/godot-cpp
- Location: `vendor/godot-cpp` (git submodule, branch 4.5)
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

### Terrain3D
- Source: https://github.com/TokisanGames/Terrain3D (Godot asset library #3892)
- Location: `addons/terrain_3d` (not yet installed)
- Pin: to be set when installed; Godot 4.7 compatibility must be confirmed first, as release 1.0.2
  advertises 4.4–4.6+.
- Licence: MIT
- Why: a maintained C++ clipmap terrain system with a 32-texture splat array, foliage instancing,
  code-driven heightmap import, optional collision, and a customisable material shader. It is the same
  architecture we would have written, so writing it ourselves buys only bugs.
- Cost if dropped: the clipmap mesh and the foliage instancer would have to be written. The collision
  bridge and our shader override are ours and portable.

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
