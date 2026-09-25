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

## Rejected

- Unreal Engine marketplace and Quixel/Megascans content. Licensed for use in Unreal Engine only. The
  restriction survives format conversion, so this content cannot enter the project in any form.
