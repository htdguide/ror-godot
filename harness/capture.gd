class_name HarnessCapture
extends RefCounted
## Writes PNG captures and their manifests.
##
## Every capture carries a manifest. The manifest is what stops goldens rotting: the
## differ refuses to compare across a different rendering driver, GPU or resolution
## rather than reporting a diff that looks like a regression but is a backend change.

const MANIFEST_VERSION: int = 1


## Absolute path of the repository-level artifact root.
##
## `res://` is the repository, since `project.godot` sits at its root — so this is not
## `res://..`, which it was while the project lived in `game/` and which wrote every artifact
## into the repository's *parent* directory for as long as the tree mirror took to notice.
## `SourceScan.repo_root()` is the same statement and the same trap.
static func artifact_root() -> String:
    return SourceScan.repo_root().path_join(HarnessCfg.ARTIFACT_ROOT).simplify_path()


## Resolves a run-relative directory to an absolute path under the artifact root.
static func resolve_dir(relative: String) -> String:
    if relative.is_absolute_path():
        return relative
    return artifact_root().path_join(relative)


static func capture_png(viewport: Viewport, path: String) -> String:
    var dir: String = path.get_base_dir()
    var err: Error = DirAccess.make_dir_recursive_absolute(dir)
    if err != OK and err != ERR_ALREADY_EXISTS:
        return "cannot create directory '%s': %s" % [dir, error_string(err)]
    var texture: ViewportTexture = viewport.get_texture()
    if texture == null:
        return "viewport has no texture; is the window rendering?"
    var image: Image = texture.get_image()
    if image == null or image.is_empty():
        return "captured image is empty; --headless renders nothing on macOS"
    var save_err: Error = image.save_png(path)
    if save_err != OK:
        return "cannot write '%s': %s" % [path, error_string(save_err)]
    return ""


## Saves a viewport as an OpenEXR, keeping values above 1.0.
##
## A PNG is 8-bit and display-encoded, so a capture through one cannot carry light: it clips at
## white and quantises in the shadows, and a ratio read off it is not a ratio of light. That cost
## this project every sun-to-sky figure it ever recorded.
##
## The viewport must have had `use_hdr_2d` set before it rendered the frame being captured.
## Without it the texture comes back RGBA8 and already clipped, and no file format recovers that
## — so this refuses rather than writing a float file full of ones.
static func capture_exr(viewport: Viewport, path: String) -> String:
    var texture: ViewportTexture = viewport.get_texture()
    if texture == null:
        return "viewport has no texture; is the window rendering?"
    var image: Image = texture.get_image()
    if image == null or image.is_empty():
        return "captured image is empty; --headless renders nothing on macOS"
    if not _is_float(image.get_format()):
        return (
            "the capture is image format %d, not float: the viewport needs use_hdr_2d set before"
            % image.get_format() + " the frame is rendered, or the values are already clipped"
        )
    var dir: String = path.get_base_dir()
    var err: Error = DirAccess.make_dir_recursive_absolute(dir)
    if err != OK and err != ERR_ALREADY_EXISTS:
        return "cannot create directory '%s': %s" % [dir, error_string(err)]
    var save_err: Error = image.save_exr(path)
    if save_err != OK:
        return "cannot write '%s': %s" % [path, error_string(save_err)]
    return ""


## The float image formats a capture can come back as.
static func _is_float(format: int) -> bool:
    return format in [
        Image.FORMAT_RH, Image.FORMAT_RGH, Image.FORMAT_RGBH, Image.FORMAT_RGBAH,
        Image.FORMAT_RF, Image.FORMAT_RGF, Image.FORMAT_RGBF, Image.FORMAT_RGBAF,
    ]


static func write_manifest(path: String, extra: Dictionary) -> String:
    var row: Dictionary = {
        "manifest_version": MANIFEST_VERSION,
        "engine": Engine.get_version_info()["string"],
        "rendering_driver": RenderingServer.get_current_rendering_driver_name(),
        "rendering_method": RenderingServer.get_current_rendering_method(),
        "gpu": RenderingServer.get_video_adapter_name(),
        "os": "%s %s" % [OS.get_name(), OS.get_version()],
        "approved_by": "",
        "approved_at": "",
    }
    row.merge(extra, true)
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return "cannot write manifest '%s': %s" % [path, error_string(FileAccess.get_open_error())]
    file.store_string(JSON.stringify(row, "  ", false) + "\n")
    file.close()
    return ""


## Puts the world into a state where numbers encoded into pixels survive to the capture:
## linear tonemapping, a black background and no ambient light.
##
## Both parts matter. A tonemapper desaturates and lifts, so a value written into one
## channel is not the value read back. And a lit background puts bright pixels all over
## the frame, which a threshold test counts as though they were geometry — the sky alone
## produced nearly two hundred thousand false positives before this existed.
static func use_measurement_environment(world: Node3D) -> void:
    var holder: WorldEnvironment = world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if holder == null or holder.environment == null:
        return
    var environment: Environment = holder.environment
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color.BLACK
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color.BLACK
    environment.ambient_light_energy = 0.0
    var ground: MeshInstance3D = world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false


## Loads a vehicle into the current world, for human sessions and ad-hoc shots. The path
## is a mod directory and a vehicle file, separated by a colon.
