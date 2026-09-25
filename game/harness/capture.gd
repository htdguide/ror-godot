class_name HarnessCapture
extends RefCounted
## Writes PNG captures and their manifests.
##
## Every capture carries a manifest. The manifest is what stops goldens rotting: the
## differ refuses to compare across a different rendering driver, GPU or resolution
## rather than reporting a diff that looks like a regression but is a backend change.

const MANIFEST_VERSION: int = 1


## Absolute path of the repository-level artifact root. Artifacts are build output of
## the repository, not of the Godot project, and shell tooling outside the project
## reads them.
static func artifact_root() -> String:
    return ProjectSettings.globalize_path("res://").path_join("..").path_join(
        HarnessCfg.ARTIFACT_ROOT
    ).simplify_path()


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
