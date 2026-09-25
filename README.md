# ror-godot

A rewrite of Rigs of Rods' renderer onto Godot 4.x, keeping Rigs of Rods' own softbody solver.

Godot is the shell: windowing, scene graph, renderer, asset loading, UI. The vehicle simulation is
Rigs of Rods' existing C++ node/beam solver, wrapped as a GDExtension. Godot's physics engine is not
used for vehicle simulation at all.

The approved plan is in [docs/PLAN.md](docs/PLAN.md). Read it before touching anything.

## Status

Repository scaffolding only. No code yet. The first code commit is the CLI harness (M0 in the plan),
which must land before any rendering work.

## Layout

    vendor/rigs-of-rods/   upstream Rigs of Rods, shallow submodule, read-only to us
    docs/                  documentation tree; see docs/README.md
    LICENSES/              one licence record per third-party asset or addon
    THIRD_PARTY.md         every third-party dependency, pinned and justified

## Requirements

- Godot 4.7.2 (installed at /Applications/Godot.app on the dev machine)
- macOS on Apple Silicon is the only supported development platform for now. Linux is deferred but
  not designed out; see the platform rules in the plan.
- A C++ toolchain for the GDExtension: clang (present), plus scons and Python (scons not yet installed)
- ffmpeg for movie contact sheets (not yet installed)

## Licence

This project links Rigs of Rods, which is GPL-3.0-or-later, so this project is
**GPL-3.0-or-later** as well. Every dependency must be GPL-3.0-compatible.
