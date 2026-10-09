class_name SourceScan
extends RefCounted
## Filesystem helpers shared by the standards gates.
##
## The standards gates are the ones that keep the codebase from rotting, so they scan
## our source only: third-party code under addons/ and vendor/ is not ours to lint, and
## linting it would produce failures nobody is allowed to fix.

const SKIP_DIRS: Array[String] = [
    ".godot", "addons", "vendor", ".git", "artifacts", "history", "assets", "bin",
]


## The repository root, which is also the Godot project root.
##
## `project.godot` sits at the repository root rather than inside `game/`, because Godot loads
## resources only from its own project directory and a top-level `harness/` is invisible to an
## engine rooted at `game/`. So `res://` is the repository, and this is not `res://..` — which it
## was while the project lived in `game/`, and which silently returned the repository's *parent*
## for one commit of the move.
static func repo_root() -> String:
    # An exported build has no repository: `res://` is inside the pack, and everything this
    # project reads by absolute path — base content, the loading picture, mods and maps — sits
    # in the folder beside the executable instead. See tools/release.sh for what goes there.
    if OS.has_feature("template"):
        return OS.get_executable_path().get_base_dir().simplify_path().trim_suffix("/")
    return ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")


## Absolute paths of every file under `root` with one of `extensions`.
static func find_files(root: String, extensions: Array[String]) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    _walk(root, extensions, out)
    out.sort()
    return out


static func _walk(dir_path: String, extensions: Array[String], out: PackedStringArray) -> void:
    var dir: DirAccess = DirAccess.open(dir_path)
    if dir == null:
        return
    for file: String in dir.get_files():
        if extensions.has(file.get_extension()):
            out.append(dir_path.path_join(file))
    for sub: String in dir.get_directories():
        if SKIP_DIRS.has(sub) or sub.begins_with("."):
            continue
        _walk(dir_path.path_join(sub), extensions, out)


static func read_lines(path: String) -> PackedStringArray:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return PackedStringArray()
    var text: String = file.get_as_text()
    file.close()
    return text.split("\n")


## Path relative to the repository root, for readable failure messages.
static func relative(path: String) -> String:
    var root: String = repo_root()
    return path.trim_prefix(root).trim_prefix("/")


## True for a line that is blank, a comment, or a documentation comment.
static func is_comment_or_blank(line: String) -> bool:
    var stripped: String = line.strip_edges()
    return stripped.is_empty() or stripped.begins_with("#")
