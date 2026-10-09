class_name BuildProfile
extends RefCounted
## Which build this checkout is: the development one or the production one.
##
## Two checkouts of the same code, told apart by one untracked file. **dev** is the testing
## build: it carries the harness fixtures, Rigs of Rods' own shipped map from the submodule, and
## content under `assets/mods` and `assets/terrains`. **prod** bundles no content at all: vehicles
## and maps live in `mods/` and `maps/` at the checkout's root, put there by whoever runs it, so
## nothing with a licence this project cannot vouch for is ever inside the build. See README.
##
## The file is `profile.cfg` at the repository root, gitignored, written by `tools/prod.sh` into
## the production worktree. Absent, the build is dev. A profile in a file rather than a branch
## difference, because a branch that differs in source from `main` would conflict on every
## transfer, and the whole point of the production branch is that it only receives.

const FILE: String = "profile.cfg"
const DEV: String = "dev"
const PROD: String = "prod"

const DEV_MOD_ROOTS: PackedStringArray = ["assets/mods", "assets/terrains"]
const DEV_TERRAIN_ROOT: String = "assets/terrains"
const DEV_SHIPPED_ROOT: String = "vendor/rigs-of-rods/content"
const DEV_DEFAULT_MAP: String = "simple2"
const PROD_MOD_ROOTS: PackedStringArray = ["mods", "maps"]
const PROD_TERRAIN_ROOT: String = "maps"


## The profile the text of a `profile.cfg` states, or dev when it states nothing it should.
## Read with the same line rule the shell's `tools/profile.sh` uses — `profile = prod`, quoted or
## not — rather than Godot's `ConfigFile`, which wants a Variant literal and reads a bare word as
## nothing.
static func parse(text: String) -> String:
    var pattern: RegEx = RegEx.new()
    pattern.compile("(?m)^\\s*profile\\s*=\\s*\"?([A-Za-z]+)\"?")
    var found: RegExMatch = pattern.search(text)
    if found == null:
        return DEV
    return PROD if found.get_string(1).to_lower() == PROD else DEV


## The profile this checkout is running as.
static func name() -> String:
    # A shipped build is the production build whatever file sits beside it: nothing bundled,
    # content from the folders beside the executable.
    if OS.has_feature("template"):
        return PROD
    var path: String = SourceScan.repo_root().path_join(FILE)
    if not FileAccess.file_exists(path):
        return DEV
    return parse(FileAccess.get_file_as_string(path))


static func is_prod() -> bool:
    return name() == PROD


## What a window and a HUD show, so nobody mistakes one build for the other.
static func label() -> String:
    return name().to_upper()


## Where vehicles are looked for, relative to the repository root. Both roots, because a pack
## decides for itself what it contains and a map's folder can hold a vehicle.
static func mod_roots() -> PackedStringArray:
    return mod_roots_of(name())


static func mod_roots_of(profile: String) -> PackedStringArray:
    return PROD_MOD_ROOTS if profile == PROD else DEV_MOD_ROOTS


## Where maps are looked for, relative to the repository root.
static func terrain_root() -> String:
    return terrain_root_of(name())


static func terrain_root_of(profile: String) -> String:
    return PROD_TERRAIN_ROOT if profile == PROD else DEV_TERRAIN_ROOT


## Where upstream's own shipped content is read from, or "" for a build that bundles none.
static func shipped_root() -> String:
    return shipped_root_of(name())


static func shipped_root_of(profile: String) -> String:
    return "" if profile == PROD else DEV_SHIPPED_ROOT


## The map a session opens on when none is named, or "" for a build that bundles none and opens
## on a flat plane with the sky over it.
static func default_map() -> String:
    return default_map_of(name())


static func default_map_of(profile: String) -> String:
    return "" if profile == PROD else DEV_DEFAULT_MAP


## The first folder a person is told to put content into.
static func mods_hint() -> String:
    return mod_roots()[0] + "/"


static func maps_hint() -> String:
    return terrain_root() + "/"
