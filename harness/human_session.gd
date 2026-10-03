class_name HumanSession
extends RefCounted
## Opens the window a person drives, and decides which kind it is.
##
## Two kinds exist and they are not variations of each other. `--play` is a map with a vehicle on
## it: the question is how the whole thing looks and behaves. `--review` is one object at a time
## on a plain stage with two buttons under it: the question is whether that object is right, and
## the answer is written down.
##
## Split from `Harness` when that file went over the source cap, and it is a seam worth having —
## everything above it is about getting a scene built, and everything here is about handing it to
## someone.


## Starts whichever human session the arguments ask for. Returns whether one was started, so the
## caller knows to stop rather than fall through to capturing a frame and exiting.
static func start(
    harness: Node, camera: Camera3D, world: Node3D, weather: String, vehicle: Dictionary
) -> bool:
    # A review window is the only place a verdict no measurement can reach gets written down:
    # three classes of content show a back face from outside while being exactly right, and
    # nothing in a file separates them from the fault. See `ReviewRig`.
    if Harness.args.has_flag("review"):
        var reviewer: ReviewRig = ReviewRig.new()
        reviewer.name = "ReviewRig"
        harness.add_child(reviewer)
        reviewer.setup(camera, world)
        print("HARNESS_REVIEW object review; close the window to exit")
        return true
    if Harness.args.has_flag("play"):
        var rig: PlayRig = PlayRig.new()
        rig.name = "PlayRig"
        harness.add_child(rig)
        rig.setup(camera, world, weather, vehicle)
        print("HARNESS_PLAY interactive mode; press Esc or close the window to exit")
        return true
    return false
