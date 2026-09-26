extends SceneTree
## Reports what grows in the valley: how many of each species, where they are and what the rules
## rejected.
##
##   godot --path game --headless --script res://tools/vegetation_probe.gd


func _initialize() -> void:
    var started: int = Time.get_ticks_usec()
    var placements: Dictionary = ValleyVegetation.place()
    var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
    var conifers: Array[Transform3D] = placements[ValleyVegetation.CONIFER_ID] as Array[Transform3D]
    var shrubs: Array[Transform3D] = placements[ValleyVegetation.SHRUB_ID] as Array[Transform3D]
    print("placed %d conifers and %d shrubs in %.0f ms" % [
        conifers.size(), shrubs.size(), elapsed_ms])

    var in_stand: int = 0
    var lowest: float = INF
    var highest: float = -INF
    var nearest_road: float = INF
    for pose: Transform3D in conifers:
        var at: Vector3 = pose.origin
        if (at.x >= ValleyLayout.STAND_WEST_M and at.x <= ValleyLayout.STAND_EAST_M
                and at.z <= ValleyLayout.STAND_NEAR_Z_M and at.z >= ValleyLayout.STAND_FAR_Z_M):
            in_stand += 1
        lowest = minf(lowest, at.y)
        highest = maxf(highest, at.y)
        nearest_road = minf(nearest_road, ValleyShape.road_distance(at.x, at.z))
    var stand_area: float = (
        absf(ValleyLayout.STAND_EAST_M - ValleyLayout.STAND_WEST_M)
        * absf(ValleyLayout.STAND_NEAR_Z_M - ValleyLayout.STAND_FAR_Z_M)
    ) / 10000.0
    print("conifers: %d in the stand (%.1f per hectare over %.1f ha), %d outside it" % [
        in_stand, float(in_stand) / stand_area, stand_area, conifers.size() - in_stand])
    print("conifers stand between %.1f m and %.1f m; the nearest is %.1f m from the road" % [
        lowest, highest, nearest_road])

    var off_ground: float = 0.0
    var checked: int = 0
    for pose: Transform3D in conifers + shrubs:
        var ground: float = ValleyShape.height_at_world(pose.origin.x, pose.origin.z)
        off_ground = maxf(off_ground, absf(pose.origin.y - ground))
        checked += 1
    print("%d plants, worst standing %.4f m off the ground" % [checked, off_ground])
    quit(0)
