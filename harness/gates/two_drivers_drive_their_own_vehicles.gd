extends GateBase
## In a split window, each half of the keyboard drives its own vehicle and nothing of the other's.
##
## Splitscreen (PLAN §0.12) hands two drivers one keyboard: the left on WASD, the right on the
## arrows (`DriveKeys`). The failure that matters is a key reaching both — Up driving both trucks
## because one map borrowed the other's key, or a gear key on one side shifting the other — and a
## person sees it as "my truck moved by itself", which is easy to put down to physics.
##
## Three checks, all against the maps a session actually uses:
##
## - **The maps are disjoint**, from each other and from every key the session answers to.
## - **Throttle moves only its own vehicle.** Two hero trucks, settled side by side; W is held for
##   three seconds through real key events, then Up. Each time one truck has to cover ground and
##   the other has to stay where it is — each run is the other's control, so a gate that saw
##   motion everywhere or nowhere would fail one of them.
## - **One-shot keys go to their owner only**: each driver's gear keys are offered to both, and
##   only the owner may take them.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const FRAME_S: float = 1.0 / 60.0
const SETTLE_FRAMES: int = 60
const HELD_FRAMES: int = 180
## Three seconds of full throttle moves the hero metres. The other truck is in gear at idle and
## creeps a few centimetres, as a real automatic does, so it is held to a share of what the driven
## one covered rather than to zero: a key reaching both would move them about equally.
const MIN_DRIVEN_M: float = 1.0
const MAX_OTHER_SHARE: float = 0.02
const APART_M: float = 8.0
const PRESET: String = "hero_3q"
## Every key the play window answers to itself, which no driver may take.
const SESSION_KEYS: Array[Key] = [
    KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_M, KEY_P, KEY_ESCAPE,
    KEY_QUOTELEFT,
]


static func meta() -> Dictionary:
    return {
        "name": "two_drivers_drive_their_own_vehicles",
        "proves": "the two split keyboard maps share no key with each other or the session, held throttle moves only its own driver's vehicle, and gear keys reach only their owner",
        "builds_on": ["rig_drives_forward"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "no shared keys; the driven truck covers at least %.0f m in %d frames while the other"
            % [MIN_DRIVEN_M, HELD_FRAMES] + " moves under %.0f%% of that, both ways round"
            % (MAX_OTHER_SHARE * 100.0)
        ),
        "why": (
            "two drivers on one keyboard fail by a key reaching both, which a person reads as"
            + " the other truck moving by itself and puts down to physics."
        ),
        "budget_s": 90.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var clash: String = _clash()
    if clash != "":
        return fail(clash)
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("maps disjoint; skipped the drive: hero asset not present at %s" % MOD_DIR, 0)

    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var drives: Array[PlayDrive] = []
    for half: int in 2:
        var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
        if (built.get("error", "") as String) != "":
            return fail(built["error"] as String)
        harness.world.add_child(built["root"] as Node3D)
        var drive: PlayDrive = PlayDrive.new()
        drive.synchronous = true
        var set_up: String = drive.setup(built)
        if set_up != "":
            return fail(set_up)
        drive.keys = DriveKeys.SPLIT_LEFT if half == 0 else DriveKeys.SPLIT_RIGHT
        drive.spawn = Vector3(APART_M * half, 0.0, 0.0)
        drives.append(drive)

    var reports: PackedStringArray = PackedStringArray()
    for owner: int in 2:
        var key: Key = (drives[owner].keys["throttle"] as Array)[0] as Key
        var moved: Array[float] = _hold(drives, key)
        var other: int = 1 - owner
        if moved[owner] < MIN_DRIVEN_M:
            return fail(
                "holding %s moved its own truck %.3f m: the key does not reach its driver"
                % [OS.get_keycode_string(key), moved[owner]],
                moved[owner]
            )
        if moved[other] > moved[owner] * MAX_OTHER_SHARE:
            return fail(
                "holding %s moved the other truck %.3f m: one key drives both"
                % [OS.get_keycode_string(key), moved[other]],
                moved[other]
            )
        reports.append("%s: own %.2f m, other %.4f m" % [
            OS.get_keycode_string(key), moved[owner], moved[other]])

    for owner: int in 2:
        for action: String in ["drive", "reverse", "neutral"]:
            var key: Key = (drives[owner].keys[action] as Array)[0] as Key
            if drives[1 - owner].on_key(key):
                return fail(
                    "%s (%s for the %s driver) was taken by the other driver"
                    % [OS.get_keycode_string(key), action, "left" if owner == 0 else "right"]
                )
            if not drives[owner].on_key(key):
                return fail("%s did not reach its own driver as %s" % [
                    OS.get_keycode_string(key), action])
        drives[owner].on_key((drives[owner].keys["drive"] as Array)[0] as Key)
    return ok("maps disjoint; " + "; ".join(reports) + "; gear keys reach their owner only", 2)


## A key both maps hold, or one a map shares with the session; "" when there is none.
func _clash() -> String:
    var seen: Dictionary = {}
    for side: Dictionary in [DriveKeys.SPLIT_LEFT, DriveKeys.SPLIT_RIGHT]:
        var label: String = "left" if side == DriveKeys.SPLIT_LEFT else "right"
        for action: String in side:
            for key: Key in side[action] as Array:
                if SESSION_KEYS.has(key):
                    return "the %s map gives %s to %s, which the session answers to" % [
                        label, OS.get_keycode_string(key), action]
                if seen.has(key) and (seen[key] as String) != label:
                    return "%s is in both maps (%s)" % [OS.get_keycode_string(key), action]
                seen[key] = label
    return ""


## Respawns both trucks, settles them, holds `key` down through a real key event for
## `HELD_FRAMES`, and returns how far each truck's frame moved. The key is always released.
func _hold(drives: Array[PlayDrive], key: Key) -> Array[float]:
    for drive: PlayDrive in drives:
        drive.respawn()
    for _f: int in SETTLE_FRAMES:
        for drive: PlayDrive in drives:
            drive.step(FRAME_S)
    var from: Array[Vector3] = []
    for drive: PlayDrive in drives:
        from.append(drive.frame.origin)
    _press(key, true)
    for _f: int in HELD_FRAMES:
        for drive: PlayDrive in drives:
            drive.step(FRAME_S)
    _press(key, false)
    var moved: Array[float] = []
    for i: int in drives.size():
        moved.append(drives[i].frame.origin.distance_to(from[i]))
    return moved


func _press(key: Key, down: bool) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.keycode = key
    event.physical_keycode = key
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
