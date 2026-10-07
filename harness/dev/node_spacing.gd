extends SceneTree
## How far apart a rig's nodes are, against how wide the things it is meant to hit are.
##
## Contact is per node: an obstacle narrower than the gap between a vehicle's nodes passes between
## them and is never touched.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    if truck.parse_file(argv[0].path_join(argv[1])) != "":
        quit(1)
        return
    var gaps: PackedFloat32Array = PackedFloat32Array()
    for i: int in truck.generated_from:
        var nearest: float = INF
        for j: int in truck.generated_from:
            if i != j:
                nearest = minf(nearest, truck.nodes[i].distance_to(truck.nodes[j]))
        gaps.append(nearest)
    var sorted: Array = Array(gaps)
    sorted.sort()
    print("%s: %d body nodes, nearest-neighbour gap median %.3f m, worst %.3f m" % [
        argv[1], gaps.size(), sorted[sorted.size() / 2], sorted[sorted.size() - 1]])
    quit(0)
