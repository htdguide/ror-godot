extends SceneTree
func _initialize() -> void:
    for hour: float in [5.5, 5.9, 6.0, 6.1, 6.2, 6.5, 7.0, 12.0]:
        var w: Dictionary = DayCycle.at(hour)
        var from: Vector3 = w.get("sun_from", Vector3.UP) as Vector3
        print("%5.2f h  elev %6.2f  lux %9.1f  ambient %8.5f  radiance %5.3f  iso %6.1f f/%.1f  sky_energy %.4f  hdri_mix %.2f" % [
            hour, rad_to_deg(asin(clampf(from.normalized().y, -1.0, 1.0))),
            float(w.get("sun_lux", 0.0)), float(w.get("ambient_energy", 0.0)),
            float(w.get("radiance_scale", 1.0)), float(w.get("iso", 0.0)),
            float(w.get("f_stop", 0.0)), float(w.get("sky_energy", 0.0)),
            float(w.get("hdri_mix", 0.0))
        ])
    quit()
