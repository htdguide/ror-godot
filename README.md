# ror-godot

A rewrite of Rigs of Rods' renderer onto Godot 4.x, keeping Rigs of Rods' own softbody solver.

Godot is the shell: windowing, scene graph, renderer, asset loading, UI. The vehicle simulation is
Rigs of Rods' existing C++ node/beam solver, wrapped as a GDExtension. Godot's physics engine is not
used for vehicle simulation at all.

The approved plan is in [docs/PLAN.md](docs/PLAN.md). Read it before touching anything.

## Status

M1 in progress: the hero truck loads from an unmodified community mod, renders, and drives on Valley
One — a 2 km generated valley with a lake, a ford, a washout, a rock shelf and a switchback
road. The softbody solver is Rigs of Rods' own laws, checked against upstream's source where a function can be
extracted. `./tools/gate.sh --all` runs the suite; `tools/play.sh --truck` opens a window and hands
over the controls. See [docs/HANDOFF.md](docs/HANDOFF.md) for where to pick up.

## Two builds: dev and prod

The same code runs as two checkouts. **dev** is this one: the harness fixtures, Rigs of Rods' own
shipped test map from the submodule, and content under `assets/mods/` and `assets/terrains/`.
**prod** bundles no content at all — vehicles go in its `mods/`, maps in its `maps/`, put there by
whoever runs it — so nothing with a licence this project cannot vouch for is ever inside the
build. `tools/prod.sh setup` creates it at `../ror-godot-prod` on the `prod` branch, marked by an
untracked `profile.cfg`; `tools/prod.sh merge` is the only way work reaches it, on your word;
`tools/prod.sh play` opens it. The window title and HUD say which build is up.

## Releases

`tools/release.sh windows` and `tools/release.sh macos` export a build from the checkout they run
in — meant for the production one — into `release/ror-godot-<platform>-<sha>.zip`: the pack, the
solver's library (a mingw cross-build for Windows, a universal dylib for macOS), Terrain3D's own
binaries, Rigs of Rods' base content, and empty `mods/` and `maps/` folders beside the executable
(beside the `.app` on macOS). A shipped build is the production build whatever made it; it opens
on a main menu — start a game as a vehicle, a map and a weather in turn; graphics options saved in
the user data folder; quit. They need
Godot's 4.7.2 export templates, and the Windows one `brew install mingw-w64`. The macOS app is
ad-hoc signed and runs here; the Windows build is tested on a Windows machine.

## Layout

    extension/             the GDExtension: Rigs of Rods' solver, decoupled from OGRE
    game/                  the Godot project: harness, gates, compatibility shim, world
    tools/                 CLI entry points; tools/gate.sh is the only way gates are run
    vendor/rigs-of-rods/   upstream Rigs of Rods, shallow submodule, read-only to us
    docs/                  documentation tree; see docs/README.md
    LICENSES/              one licence record per third-party asset or addon
    THIRD_PARTY.md         every third-party dependency, pinned and justified

## Requirements

- Godot 4.7.2 (installed at /Applications/Godot.app on the dev machine)
- macOS on Apple Silicon is the only supported development platform for now. Linux is deferred but
  not designed out; see the platform rules in the plan.
- A C++ toolchain for the GDExtension: clang, scons and Python. `cd extension && scons
  target=template_debug` rebuilds `bin/librorbridge*.dylib`, which is not committed.
- ffmpeg for movie contact sheets (not yet installed)

## Licence

This project links Rigs of Rods, which is GPL-3.0-or-later, so this project is
**GPL-3.0-or-later** as well. Every dependency must be GPL-3.0-compatible.
