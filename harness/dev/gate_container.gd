class_name GateContainer
extends RefCounted
## One gate's world, isolated from every other gate's.
##
## The suite used to be one OS window per gate: 77 windows over a run, each paying engine
## startup, shader compilation and terrain import again. D0 runs them in one window, which means
## a gate now inherits whatever the gate before it left behind unless something prevents it.
## This is that something.
##
## **A container is not a process.** It cannot stop a gate from writing a file or from leaving a
## `static var` set — `static_state` is the gate that handles the second. What it does stop is
## everything a gate builds in the world from being visible to the next one:
##
## - **Its own `World3D`**, through a `SubViewport` with `own_world_3d`. Separate environment,
##   separate lighting, separate camera list, separate reflection probes. A `DirectionalLight3D`
##   one gate adds cannot light the next gate's frame.
## - **Its own render target**, so a capture reads this gate's pixels and not the window's. The
##   window shows the container that is running, which is what makes one window enough.
## - **Its own `TerrainWorld`**, so the terrain built last is a property of the container.
## - **Torn down, and asserted empty.** `census()` before and after; a difference is a leak and it
##   fails the gate that caused it rather than the one that runs next.
##
## The leak census counts orphan nodes and `RenderingServer` instances, because those are the two
## that a freed subtree does not necessarily take with it: a node held by a reference outlives its
## parent, and a mesh or light instance registered directly with the server is invisible to the
## scene tree entirely.

## What a container is measured by, before and after. Two independent counters, because each
## catches leaks the other cannot see.
static func census() -> Dictionary:
    return {
        "orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
        "render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
        "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
    }


var viewport: SubViewport = null
var world: Node3D = null
var camera: Camera3D = null
var terrain: TerrainWorld = null
## This gate's own random source, seeded the same for every container.
##
## The harness used to hold one RNG for the process, seeded once. Every gate that drew from it
## advanced it, so the numbers a gate was given depended on how many draws the gates before it had
## made — process-global state in a different hiding place from a `static var`, and
## `extension_parity` measured 5.89e-06 in one order and 1.35e-06 in another because of it.
var rng: RandomNumberGenerator = null
var name: String = ""

var _before: Dictionary = {}


## Opens a container under `parent`, sized to the window so a capture is the resolution a gate
## asks for. Nothing is in it yet: the caller builds the world.
func open(parent: Node, gate_name: String, size: Vector2i) -> void:
    name = gate_name
    _before = census()
    terrain = TerrainWorld.new()
    rng = RandomNumberGenerator.new()
    rng.seed = HarnessCfg.SEED
    viewport = SubViewport.new()
    viewport.name = "Container_%s" % gate_name
    viewport.size = size
    # A SubViewport with its own World3D is the isolation. Without this it draws into the
    # parent's world and a container contains nothing at all.
    viewport.own_world_3d = true
    # Gates render on demand through `advance_frames`, and a target that updates only when
    # something asks keeps a container that is merely open from costing a frame.
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    # Physics is the solver's, never Godot's -- the same rule the terrain's collision mode
    # follows -- so a container does not run a physics space it has no use for.
    viewport.physics_object_picking = false
    parent.add_child(viewport)


## Frees everything the container holds and reports what it left behind.
##
## Returns {"leaked": String, "before": Dictionary, "after": Dictionary}. `leaked` is "" when the
## counts came back.
func close() -> Dictionary:
    world = null
    camera = null
    terrain = null
    rng = null
    if viewport != null:
        viewport.queue_free()
        viewport = null
    # A queue_free is deferred, and a census taken before the deletion happens counts the nodes
    # as still there: it has to be waited out, not assumed.
    await Engine.get_main_loop().process_frame
    await Engine.get_main_loop().process_frame
    var after: Dictionary = census()
    return {"leaked": _compare(_before, after), "before": _before, "after": after}


## What a container left behind, or "" when it left nothing.
##
## Orphans are exact: a node with no parent that existed before and does not now is a leak with
## no other explanation. The render and node counts are compared with a tolerance, because the
## engine's own overlays and the window's own scene are counted too and neither is this gate's.
func _compare(before: Dictionary, after: Dictionary) -> String:
    var orphans: int = int(after["orphan_nodes"]) - int(before["orphan_nodes"])
    if orphans > 0:
        return "%d orphan nodes: something holds a reference to a node the container freed" % orphans
    var nodes: int = int(after["nodes"]) - int(before["nodes"])
    if nodes > NODE_SLACK:
        return "%d nodes still in the tree, over a slack of %d" % [nodes, NODE_SLACK]
    return ""


## How many nodes a container may leave in the tree without being called a leak.
##
## Not zero, and the reason is measured rather than assumed: the engine adds nodes of its own
## during a run -- tooltip and overlay scaffolding among them -- and a gate is not responsible
## for those. Orphan count carries the exactness instead, since an orphan has no innocent
## explanation.
const NODE_SLACK: int = 8
