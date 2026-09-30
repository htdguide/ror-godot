class_name TruckLexer
extends RefCounted
## How a Rigs of Rods vehicle file is cut into sections, rows and fields.
##
## The format has no punctuation to tell the three apart, so every rule here is a judgement
## about a bare line of text, and each one exists because getting it wrong invents data:
##
## A section header is a bare word on its own line — but a lone number is data, because
## sections like `minimass` hold a single value, and reading that as a header loses the
## value and every line after it. A `torquecurve` body may also be a single bare word, the
## name of one of upstream's predefined models, which is why the current section is part of
## the decision.
##
## A directive is not a section row. It may appear anywhere, it carries no section header,
## and it looks exactly like data to a parser that only tracks the last header it saw. Left
## unhandled the hero truck's `set_node_defaults` and `set_beam_defaults` lines, which sit
## just after its cinecam section, parse as two more cinecams at (0, -1, 1.06) and
## (0, 4000000, 150) — one of them a spring value read as a camera position.
##
## And a file's metadata lines are a third case: `author`, `fileinfo` and `guid` are
## keywords with their arguments on the same line and belong to no section at all. The hero
## truck states all three immediately after its `globals` row, so read as data they are
## three more globals rows — and its `guid` line, whose value begins `410e0145`, parses as a
## cargo mass of 410 times ten to the 145th kilograms.
##
## Fields are separated by commas, tabs or runs of spaces, all three of which real files
## mix within one row.

const COMMENT_PREFIXES: Array[String] = [";", "//"]

## Keywords that carry their arguments on the same line and belong to no section. They are
## recognised so that they are not read as rows of whatever section preceded them.
## `description` and `comment` open blocks; their contents are skipped in the same way,
## which is enough while nothing reads them.
const METADATA_KEYWORDS: Array[String] = [
    "author",
    "fileinfo",
    "guid",
    "description",
    "end_description",
    "comment",
    "end_comment",
    "sectionconfig",
    "add_animation",
    "prop_camera_mode",
    "flexbody_camera_mode",
    "speedlimiter",
    "extcamera",
]

## `forset` is deliberately absent: it belongs to the flexbody above it and that section
## consumes it itself.
const DIRECTIVES: Array[String] = [
    "set_node_defaults",
    "set_beam_defaults",
    "set_beam_defaults_scale",
    "set_inertia_defaults",
    "set_default_minimass",
    "set_managedmaterials_options",
    "set_skeleton_settings",
    "detacher_group",
    "enable_advanced_deformation",
    "disable_default_sounds",
    "end_section",
]


## Strips a comment and surrounding whitespace. Returns "" for a line with no content.
static func strip(raw: String) -> String:
    var line: String = raw.strip_edges()
    for prefix: String in COMMENT_PREFIXES:
        var at: int = line.find(prefix)
        if at == 0:
            return ""
        if at > 0:
            line = line.substr(0, at).strip_edges()
    return line


static func fields(line: String) -> PackedStringArray:
    var normalised: String = line.replace("\t", ",").replace(" ", ",")
    var out: PackedStringArray = PackedStringArray()
    for field: String in normalised.split(","):
        var trimmed: String = field.strip_edges()
        if not trimmed.is_empty():
            out.append(trimmed)
    return out


## Whether `line` opens a new section, given the section currently open.
static func is_section_header(line: String, current_section: String) -> bool:
    if line.contains(",") or line.contains(" ") or line.contains("\t"):
        return false
    if line.is_valid_float() or line.is_valid_int():
        return false
    if current_section == "torquecurve" and TorqueCurves.has(line):
        return false
    return true


## The directive this line states, or "" when it is data.
##
## The keyword has to end at a separator, because one directive's name is a prefix of
## another's: `set_beam_defaults_scale` begins with `set_beam_defaults`. Matched on the
## prefix alone it was read as a `set_beam_defaults` whose first argument was the text
## `_scale`, which parses as zero — so every beam declared before the file's first real
## `set_beam_defaults` was given a spring of 0 N/m, and the scale itself never applied.
static func directive_of(line: String) -> String:
    for directive: String in DIRECTIVES:
        if _states_keyword(line, directive):
            return directive
    return ""


## Whether this line is a metadata keyword rather than a row of the open section.
static func is_metadata(line: String) -> bool:
    for keyword: String in METADATA_KEYWORDS:
        if _states_keyword(line, keyword):
            return true
    return false


## Whether `line` is `keyword`, alone or followed by its arguments. A keyword runs to a
## separator or to the end of the line, never into the middle of a longer word.
static func _states_keyword(line: String, keyword: String) -> bool:
    if line == keyword:
        return true
    if not line.begins_with(keyword) or line.length() <= keyword.length():
        return false
    var next: String = line[keyword.length()]
    return next == " " or next == "\t" or next == ","


## The arguments of a directive line, with the keyword removed.
static func directive_fields(line: String, directive: String) -> PackedStringArray:
    return fields(line.substr(directive.length()))
