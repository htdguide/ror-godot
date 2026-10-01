extends SceneTree
## What is actually lighting a world: the environment's ambient settings and every light in it.
##
##   godot --path . --headless --script res://harness/dev/light_probe.gd


func _initialize() -> void:
    for preset: String in ["noon_clear", "golden_dusk"]:
        var world: Node3D = BlockoutWorld.build(WeatherCfg.get_preset(preset), false, false)
        root.add_child(world)
        print("=== %s ===" % preset)
        var holder: WorldEnvironment = world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
        if holder != null and holder.environment != null:
            var env: Environment = holder.environment
            print("  ambient_light_source      %d (0=BG 1=DISABLED 2=COLOR 3=SKY)"
                % env.ambient_light_source)
            print("  ambient_light_energy      %.3f" % env.ambient_light_energy)
            print("  ambient_light_sky_contrib %.3f" % env.ambient_light_sky_contribution)
            print("  reflected_light_source    %d" % env.reflected_light_source)
            print("  background_mode           %d" % env.background_mode)
            print("  sky material              %s" % (
                env.sky.sky_material.get_class() if env.sky != null and env.sky.sky_material != null
                else "<none>"
            ))
            if env.sky != null:
                print("  sky process_mode          %d (0=AUTO 1=HIGH_QUALITY 2=HQ_INCR 3=REALTIME)"
                    % env.sky.process_mode)
        for child: Node in world.get_children():
            var light: Light3D = child as Light3D
            if light == null:
                continue
            print("  light %-6s energy %.3f  sky_mode %d  colour %v" % [
                light.name, light.light_energy, light.sky_mode,
                Vector3(light.light_color.r, light.light_color.g, light.light_color.b)
            ])
        world.queue_free()
    quit()
