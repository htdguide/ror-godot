extends GateBase
## Every third-party dependency is recorded, pinned and licensed before it ships.
##
## The rule in docs/PLAN.md §0 is that nothing third-party is adopted without approval and
## that every adoption lands with a source, a version pin, a licence and an attribution.
## Written down, that rule decays; checked, it cannot. This is the check.
##
## Licences are gated, not trusted, for a practical reason rather than a legal one: this
## project links GPL-3.0 code and is therefore GPL-3.0-or-later itself, so a dependency
## under an incompatible licence is not a paperwork problem but a project-ending one. And
## engine-locked content — Unreal marketplace, Quixel Megascans — is rejected by name,
## because that restriction survives format conversion and is the easiest way to poison a
## project permanently.

const RECORD_DIR: String = "LICENSES"
const REGISTER: String = "THIRD_PARTY.md"
## Every submodule must be recorded, and every addon that ships inside the game.
const ADDON_DIR: String = "game/addons"
## Marketplace content whose licence forbids use outside its own engine. Matched against
## file and directory names anywhere in the tree.
const ENGINE_LOCKED: Array[String] = ["megascans", "quixel", "unrealmarketplace", "unreal_marketplace"]
## Directories this project writes itself and never ships. They are in `.gitignore`, nothing
## third-party can arrive in them, and `history/` in particular is unbounded by design — it holds
## every captured frame of every run ever made, which on this machine is 1099 runs and 179 GB. A
## scan that walks it is a scan that gets slower every time the suite is used, and this one did:
## it ran in 27.5 s this morning and 36.1 s by the afternoon, against a 30 s budget, and failed
## every commit in between on nothing but its own output.
const OWN_OUTPUT: Array[String] = ["history", "artifacts", "build", "bin", ".godot", ".git"]
## An entry has to say these things, not merely exist. A pin is among them because the rule
## is that no dependency floats: a branch or a tag that moves is not a version.
const REQUIRED_FIELDS: Array[String] = ["Source:", "Pin:", "Licence:", "Why:"]
## Phrases that mean an entry is a plan rather than a record. An entry saying a dependency
## is not yet installed must not satisfy the requirement for one that is.
const UNRESOLVED: Array[String] = ["not yet installed", "to be set", "tbd"]


static func meta() -> Dictionary:
    return {
        "name": "asset_licenses",
        "proves": "every submodule and shipped addon is registered in THIRD_PARTY.md with a source, a licence and a reason, and engine-locked content is absent",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 unregistered dependencies, 0 entries missing a required field, 0 engine-locked assets",
        "why": (
            "this project links GPL-3.0 code, so an incompatible dependency is not a"
            + " paperwork problem but a project-ending one, and engine-locked marketplace"
            + " content stays engine-locked through any format conversion. Both are cheap"
            + " to check now and impossible to undo later."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    var register: String = _read(root.path_join(REGISTER))
    if register.is_empty():
        return fail("%s is missing or empty: nothing records what this project depends on" % REGISTER)

    var sections: Array[Dictionary] = _sections(register)
    var offenders: PackedStringArray = PackedStringArray()
    var checked: PackedStringArray = PackedStringArray()
    for name: String in _submodules(root):
        checked.append(name)
        offenders.append_array(_check(sections, "submodule", name))
    for name: String in _addons(root):
        checked.append(name)
        offenders.append_array(_check(sections, "addon", name))

    # A record file per licence, so the licence text ships with the project rather than
    # being a claim in a table.
    var records: PackedStringArray = _records(root)
    if not checked.is_empty() and records.is_empty():
        offenders.append("%s/ holds no licence text for %d dependencies" % [RECORD_DIR, checked.size()])

    var locked: PackedStringArray = _engine_locked(root)
    for path: String in locked:
        offenders.append("engine-locked content: %s" % path)

    if offenders.size() > 0:
        return fail("; ".join(offenders), offenders.size())
    return ok(
        "%d dependencies registered (%s), %d licence records, no engine-locked content"
        % [checked.size(), ", ".join(checked), records.size()],
        0
    )


func _read(path: String) -> String:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text: String = file.get_as_text()
    file.close()
    return text


## Submodule paths, read from .gitmodules so a new one cannot be added without being seen.
func _submodules(root: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for line: String in _read(root.path_join(".gitmodules")).split("\n"):
        var trimmed: String = line.strip_edges()
        if trimmed.begins_with("path ="):
            out.append(trimmed.trim_prefix("path =").strip_edges().get_file())
    return out


## Addons installed into the game. Generated addons are absent from a fresh checkout, which
## is not a failure: what matters is that anything present is registered.
func _addons(root: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var dir: DirAccess = DirAccess.open(root.path_join(ADDON_DIR))
    if dir == null:
        return out
    for name: String in dir.get_directories():
        out.append(name)
    return out


func _records(root: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var dir: DirAccess = DirAccess.open(root.path_join(RECORD_DIR))
    if dir == null:
        return out
    for name: String in dir.get_files():
        out.append(name)
    return out


## The register split into its `###` entries, as {"title", "body"}.
func _sections(register: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var title: String = ""
    var body: String = ""
    for line: String in register.split("\n"):
        if line.begins_with("### "):
            if title != "":
                out.append({"title": title, "body": body})
            title = line.trim_prefix("### ").strip_edges()
            body = ""
            continue
        body += line + "\n"
    if title != "":
        out.append({"title": title, "body": body})
    return out


## What is wrong with one dependency's entry, if anything.
##
## The entry is found by name rather than by an exact heading, so renaming a heading does not
## silently un-register something — but it must be a real entry: one that states a pin and
## does not describe the dependency as a plan. An entry saying "not yet installed" used to
## satisfy this check for a dependency that was, by then, installed.
func _check(sections: Array[Dictionary], kind: String, name: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var needle: String = name.to_lower()
    for section: Dictionary in sections:
        var haystack: String = (
            (section["title"] as String) + " " + (section["body"] as String)
        ).to_lower()
        if not haystack.contains(needle):
            continue
        for field: String in REQUIRED_FIELDS:
            if not (section["body"] as String).contains(field):
                out.append(
                    "%s '%s' is recorded under '%s' with no '%s' field"
                    % [kind, name, section["title"], field]
                )
        for phrase: String in UNRESOLVED:
            if haystack.contains(phrase):
                out.append(
                    "%s '%s' is recorded under '%s' as '%s', but it is installed"
                    % [kind, name, section["title"], phrase]
                )
        return out
    return PackedStringArray(["%s '%s' has no %s entry" % [kind, name, REGISTER]])


func _engine_locked(root: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    _scan_locked(root, out, 0)
    return out


func _scan_locked(path: String, out: PackedStringArray, depth: int) -> void:
    # Deep enough to reach an asset pack dropped anywhere sensible, shallow enough not to
    # walk every vendored source tree.
    if depth > 4:
        return
    var dir: DirAccess = DirAccess.open(path)
    if dir == null:
        return
    for name: String in dir.get_directories():
        if name.begins_with(".") or (depth == 0 and OWN_OUTPUT.has(name)):
            continue
        if _is_engine_locked(name):
            out.append(SourceScan.relative(path.path_join(name)))
            continue
        _scan_locked(path.path_join(name), out, depth + 1)
    for name: String in dir.get_files():
        if _is_engine_locked(name):
            out.append(SourceScan.relative(path.path_join(name)))


func _is_engine_locked(name: String) -> bool:
    var lower: String = name.to_lower()
    for marker: String in ENGINE_LOCKED:
        if lower.contains(marker):
            return true
    return false
