class_name MoneyShotFrames
extends RefCounted
## Where the money shots stand, each derived from something the terrain declares.
##
## PLAN §0.5's rule, after the first set named features of a valley that no longer exists: a frame
## is placed from a feature the *terrain* declares — its spawn, its objects, its roads, its water —
## or from a search over its own heightmap, never from a coordinate written down beside it. So
## every function here takes the terrain and asks it. A terrain with no roads or no water still
## gets a frame, from the feature it does have, and says which.
##
## Each frame is {"name", "eye", "at", "focal_mm", "weather", "subject", "from"}: `subject` is
## what the frame is of and `from` is the terrain feature it was derived from, both for the sheet
## and for the gate's report.

## How coarsely the heightmap is searched for its high and low ground: every 32nd cell of 2048 is a
## sample every 62 m, which finds a hill rather than a boulder.
const LANDMARK_STRIDE: int = 32
## How far the shoreline search walks out from the spawn before giving up, in cells.
const SHORE_SEARCH_CELLS: int = 400
## How near the water a cell's ground has to be to count as the shore, in metres.
const SHORE_BAND_M: float = 0.6
## Eye heights: a person standing, a lookout, a chase camera.
const EYE_M: float = 1.6
const LOOKOUT_UP_M: float = 24.0
const LOOKOUT_BACK_M: float = 60.0


## The eight frames, in sheet order.
static func frames(terrain: RorTerrain, hero: Dictionary) -> Array[Dictionary]:
    var spawn: Vector3 = _on_ground(terrain, terrain.start_position(), 0.0)
    var sun_toward: Vector3 = _sun_toward("golden_dusk")
    var road: Dictionary = _road_near(terrain, spawn, sun_toward)
    var shore: Dictionary = _shore_near(terrain, spawn)
    var high: Vector3 = _landmark(terrain, true)
    var prop: Dictionary = _prop_near(terrain, spawn)
    var bounds: AABB = hero["bounds"] as AABB
    var centre: Vector3 = bounds.position + bounds.size * 0.5
    var reach: float = maxf(bounds.size.length(), 1.0)
    var wheel: Vector3 = hero["wheel"] as Vector3
    return [
        {
            "name": "vista", "weather": "golden_dusk", "focal_mm": 35.0,
            "eye": _stand(terrain, high, spawn, LOOKOUT_BACK_M, LOOKOUT_UP_M), "at": spawn,
            "subject": "the map from its highest ground", "from": "heightmap maximum",
        },
        {
            "name": "road_into_the_sun", "weather": "golden_dusk", "focal_mm": 35.0,
            "eye": road["eye"], "at": road["at"],
            "subject": "the terrain's own road, lit from ahead", "from": road["from"],
        },
        {
            "name": "shoreline", "weather": "golden_dusk", "focal_mm": 40.0,
            "eye": shore["eye"], "at": shore["at"],
            "subject": "where the water meets the ground", "from": shore["from"],
        },
        {
            "name": "hero_at_spawn", "weather": "noon_clear", "focal_mm": 50.0,
            "eye": centre + Vector3(-reach * 0.9, reach * 0.5, reach * 0.9), "at": centre,
            "subject": "the hero vehicle where the terrain spawns it", "from": "terrn2 spawn",
        },
        {
            "name": "headlights", "weather": "night_moon", "focal_mm": 35.0, "lamps": true,
            # A chase camera low behind the vehicle, or the next place round it that is not
            # inside a building: a port spawns its trucks between walls.
            "eyes": [
                centre + Vector3(reach * 1.4, reach * 0.3, reach * 0.5),
                centre + Vector3(reach * 0.5, reach * 0.3, reach * 1.4),
                centre + Vector3(-reach * 1.4, reach * 0.3, reach * 0.5),
                centre + Vector3(-reach * 0.5, reach * 0.3, -reach * 1.4),
            ],
            "eye": centre + Vector3(reach * 1.4, reach * 0.3, reach * 0.5), "at": centre,
            "subject": "the hero at night with its lamps on", "from": "terrn2 spawn",
        },
        {
            "name": "object", "weather": "noon_clear", "focal_mm": 50.0,
            "eye": _stand(terrain, prop["at"] as Vector3, spawn, 9.0, 3.0), "at": prop["at"],
            "subject": "one of the terrain's own objects", "from": prop["from"],
        },
        {
            "name": "fog_road", "weather": "fog_bank", "focal_mm": 35.0,
            "eye": road["eye"], "at": road["at"],
            "subject": "the same road in a 300 m fog", "from": road["from"],
        },
        {
            "name": "wheel_macro", "weather": "noon_clear", "focal_mm": 85.0,
            "eye": wheel + Vector3(-1.6, 0.35, 1.9), "at": wheel,
            "subject": "the hero's front wheel on the terrain's own surface",
            "from": "hero wheel node",
        },
    ]


## A point on the terrain's road network nearest the spawn, looked along toward whichever end is
## more into the sun. A terrain with no road points gets the spawn itself, and says so.
static func _road_near(terrain: RorTerrain, spawn: Vector3, sun_toward: Vector3) -> Dictionary:
    var best: Dictionary = {}
    var best_distance: float = INF
    for group: Array in RorProceduralRoad.groups(terrain):
        for index: int in group.size():
            var point: Dictionary = group[index] as Dictionary
            var at: Vector3 = point["position"] as Vector3
            var distance: float = Vector2(at.x - spawn.x, at.z - spawn.z).length()
            if distance < best_distance and group.size() > 1:
                best_distance = distance
                best = {"group": group, "index": index}
    if best.is_empty():
        return {
            "eye": spawn + Vector3(0.0, EYE_M, 0.0) - sun_toward * 8.0,
            "at": spawn + sun_toward * 40.0, "from": "no road points: the spawn, facing the sun",
        }
    var group: Array = best["group"] as Array
    var index: int = best["index"] as int
    var here: Vector3 = (group[index] as Dictionary)["position"] as Vector3
    var ahead: Vector3 = (group[mini(index + 1, group.size() - 1)] as Dictionary)["position"]
    var behind: Vector3 = (group[maxi(index - 1, 0)] as Dictionary)["position"]
    var forward: Vector3 = (ahead - here) if ahead != here else (here - behind)
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    if forward.dot(sun_toward) < 0.0:
        forward = -forward
    var eye: Vector3 = _on_ground(terrain, here - forward * 6.0, EYE_M)
    return {
        "eye": eye, "at": eye + forward * 60.0 + Vector3(0.0, -1.0, 0.0),
        "from": "road point %d of %d, %.0f m from the spawn" % [index + 1, group.size(), best_distance],
    }


## The shoreline nearest the spawn: the first heightmap cell, walking out in rings, whose ground
## sits within a band of the water the file declares. No water means the lowest ground instead.
static func _shore_near(terrain: RorTerrain, spawn: Vector3) -> Dictionary:
    if not RorWater.declares_water(terrain):
        var low: Vector3 = _landmark(terrain, false)
        return {"at": low, "eye": _stand(terrain, low, spawn, 22.0, 6.0),
                "from": "no water declared: the lowest ground"}
    var water: float = RorWater.height_at(terrain)
    var grid: Dictionary = terrain.lattice()
    var size: int = grid["size"] as int
    var spacing: float = grid["spacing"] as float
    var cx: int = clampi(int(spawn.x / spacing), 0, size - 1)
    var cz: int = clampi(int(spawn.z / spacing), 0, size - 1)
    for ring: int in range(1, SHORE_SEARCH_CELLS):
        for z: int in range(cz - ring, cz + ring + 1):
            for x: int in [cx - ring, cx + ring]:
                var found: Dictionary = _shore_cell(terrain, x, z, size, spacing, water)
                if not found.is_empty():
                    return found
        for x: int in range(cx - ring + 1, cx + ring):
            for z: int in [cz - ring, cz + ring]:
                var found: Dictionary = _shore_cell(terrain, x, z, size, spacing, water)
                if not found.is_empty():
                    return found
    var low: Vector3 = _landmark(terrain, false)
    return {"at": low, "eye": _stand(terrain, low, spawn, 22.0, 6.0),
            "from": "water declared but no shore found: the lowest ground"}


## A cell is the shore when its ground is at the water line and a neighbour's is under it: the
## camera stands on the land side and looks across the edge onto the water.
static func _shore_cell(
    terrain: RorTerrain, x: int, z: int, size: int, spacing: float, water: float
) -> Dictionary:
    if x < 1 or z < 1 or x >= size - 1 or z >= size - 1:
        return {}
    var height: float = terrain.height_at(x, z)
    if absf(height - water) > SHORE_BAND_M:
        return {}
    for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
        if terrain.height_at(x + step.x, z + step.y) < water - SHORE_BAND_M:
            var edge: Vector3 = Vector3(float(x) * spacing, water, float(z) * spacing)
            var seaward: Vector3 = Vector3(float(step.x), 0.0, float(step.y))
            return {
                "at": edge + seaward * 25.0,
                "eye": _on_ground(terrain, edge - seaward * 18.0, 6.0),
                "from": "heightmap cell %d,%d at the WaterLine %.1f m, water beyond it" % [x, z, water],
            }
    return {}


## The terrain's highest or lowest sampled ground.
static func _landmark(terrain: RorTerrain, highest: bool) -> Vector3:
    var grid: Dictionary = terrain.lattice()
    var size: int = grid["size"] as int
    var spacing: float = grid["spacing"] as float
    var best: Vector3 = Vector3(0.0, -INF if highest else INF, 0.0)
    for z: int in range(0, size, LANDMARK_STRIDE):
        for x: int in range(0, size, LANDMARK_STRIDE):
            var height: float = terrain.height_at(x, z)
            if (highest and height > best.y) or (not highest and height < best.y):
                best = Vector3(float(x) * spacing, height, float(z) * spacing)
    return best


## The terrain's own object nearest the spawn that is a thing rather than the map's furniture.
static func _prop_near(terrain: RorTerrain, spawn: Vector3) -> Dictionary:
    var best: Vector3 = spawn
    var best_name: String = ""
    var best_distance: float = INF
    for placement: Dictionary in RorObjects.placements(terrain):
        var name: String = (placement["name"] as String).to_lower()
        if name.contains("horizon") or name.contains("base") or name.contains("sky"):
            continue
        var at: Vector3 = placement["position"] as Vector3
        var distance: float = Vector2(at.x - spawn.x, at.z - spawn.z).length()
        if distance < best_distance:
            best_distance = distance
            best = at
            best_name = placement["name"] as String
    if best_name == "":
        return {"at": spawn, "from": "no objects placed: the spawn"}
    return {"at": best, "from": "object '%s', %.0f m from the spawn" % [best_name, best_distance]}


## Where to stand to look at `at` from the side the spawn is on: back toward the spawn, up, kept
## inside the map and above the ground it is over.
static func _stand(terrain: RorTerrain, at: Vector3, toward: Vector3, back: float, up: float) -> Vector3:
    var away: Vector3 = Vector3(toward.x - at.x, 0.0, toward.z - at.z)
    away = away.normalized() if away.length() > 1.0 else Vector3(-1.0, 0.0, -1.0).normalized()
    return _on_ground(terrain, at + away * back, up)


## A point put on the terrain's ground plus a height, kept inside the map.
static func _on_ground(terrain: RorTerrain, at: Vector3, up: float) -> Vector3:
    var grid: Dictionary = terrain.lattice()
    var span: float = float((grid["size"] as int) - 1) * (grid["spacing"] as float)
    var x: float = clampf(at.x, 2.0, span - 2.0)
    var z: float = clampf(at.z, 2.0, span - 2.0)
    return Vector3(x, terrain.height_at_world(x, z) + up, z)


## The direction the sun's light comes from under a weather, flattened to the ground.
static func _sun_toward(weather: String) -> Vector3:
    var preset: Dictionary = WeatherCfg.get_preset(weather)
    var from: Vector3 = preset.get("sun_from", Vector3(0.0, 1.0, 0.0)) as Vector3
    var flat: Vector3 = Vector3(from.x, 0.0, from.z)
    return flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
