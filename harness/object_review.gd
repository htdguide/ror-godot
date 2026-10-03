class_name ObjectReview
extends RefCounted
## What a person has said about a terrain object, kept between sessions.
##
## **This is the one oracle nothing else in the suite can replace.** Three classes of content
## show a back face from outside while being exactly right — a single-card road sign, a pair of
## parallel facades with no end walls, a shell with no roof — and nothing in a file separates
## them from a wall that is genuinely turned round. `an_object_is_not_a_hole_from_outside` counts
## and reports for that reason. A person looking at the object settles it in a second, and the
## only thing missing was somewhere to put the answer.
##
## So the answers live here, in the tree, under version control. They are not a golden: nothing
## compares a render against them and no gate writes one. They are a record of what a human
## being said about a named mesh, with the date they said it, and the only thing that writes one
## is `tools/review.sh` with a person pressing the key.
##
## **Keyed by mesh file, not by terrain.** Starling Island's four maps share almost all of their
## objects and so do the packs; `haus4.mesh` looks the same wherever it is placed, and a judgement
## about it is a judgement about it everywhere.

const PATH: String = "res://harness/reference/object_review.json"
const PASS: String = "pass"
const FAIL: String = "fail"


## Every verdict on record, as `{mesh file: {"verdict", "at", "note", "marks"}}`.
static func load_all() -> Dictionary:
    var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is not Dictionary:
        return {}
    var verdicts: Variant = (parsed as Dictionary).get("verdicts", {})
    return verdicts as Dictionary if verdicts is Dictionary else {}


## Records one verdict and writes the file. Returns an error, or "".
##
## Written whole each time rather than appended: the file is a few hundred lines at most, and a
## half-written record of what a person said is worse than none.
static func record(
    mesh_file: String, verdict: String, note: String = "", marks: Array = []
) -> String:
    var verdicts: Dictionary = load_all()
    verdicts[mesh_file] = {
        "verdict": verdict,
        "at": Time.get_datetime_string_from_system(true, true) + "Z",
        "note": note,
        # Which surfaces the person pointed at, as `ReviewPick.describe` writes them: the
        # submesh, a triangle in it, how many triangles the surface has, its area, and which way
        # it looks in the object's own axes. A sentence says what is wrong; this says where.
        "marks": marks,
    }
    return _write(verdicts)


## Forgets one verdict, so the object comes back round. Returns an error, or "".
static func forget(mesh_file: String) -> String:
    var verdicts: Dictionary = load_all()
    if not verdicts.has(mesh_file):
        return ""
    verdicts.erase(mesh_file)
    return _write(verdicts)


## The whole record for one mesh, or empty.
static func record_of(mesh_file: String) -> Dictionary:
    var found: Variant = load_all().get(mesh_file, null)
    return found as Dictionary if found is Dictionary else {}


## Which meshes carry one verdict.
static func with_verdict(verdict: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var verdicts: Dictionary = load_all()
    for mesh_file: String in verdicts.keys():
        if verdict_of(mesh_file) == verdict:
            out.append(mesh_file)
    return out


## What a person said about one mesh, or "" if nobody has.
static func verdict_of(mesh_file: String) -> String:
    var record: Variant = load_all().get(mesh_file, null)
    if record is not Dictionary:
        return ""
    return (record as Dictionary).get("verdict", "") as String


## How many have been passed and how many failed, as `{"pass", "fail"}`.
static func tally() -> Dictionary:
    var passed: int = 0
    var failed: int = 0
    for mesh_file: String in load_all().keys():
        if verdict_of(mesh_file) == PASS:
            passed += 1
        elif verdict_of(mesh_file) == FAIL:
            failed += 1
    return {"pass": passed, "fail": failed}


## Sorted by name, so a diff of this file reads as a list of judgements rather than as a list of
## the order somebody happened to press the keys in.
static func _write(verdicts: Dictionary) -> String:
    var names: Array = verdicts.keys()
    names.sort()
    var ordered: Dictionary = {}
    for name: String in names:
        ordered[name] = verdicts[name]
    var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
    if file == null:
        return "cannot write %s" % PATH
    file.store_string(JSON.stringify(
        {"version": 1, "verdicts": ordered}, "  ", true
    ) + "\n")
    file.close()
    return ""
