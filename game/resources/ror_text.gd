class_name RorText
extends RefCounted
## The small shared habits of Rigs of Rods' text formats.
##
## Its configs are hand-edited files from twenty years of contributors: comments start with `#`,
## `;` or `//` depending on the file, values are separated by commas with arbitrary whitespace,
## and a file is not necessarily UTF-8 — La Paz's own ground model config is Latin-1, and reading
## it as UTF-8 returns nothing at all with the message "stream did not contain valid UTF-8".
##
## So text is read as bytes and decoded permissively. The alternative is a parser that works on
## every file until it meets one a person edited in Notepad in 2009.


## Reads a file as text, whatever its encoding. Returns "" when it cannot be read at all.
static func read(path: String) -> String:
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        return ""
    var text: String = bytes.get_string_from_utf8()
    if text.is_empty():
        # Latin-1: every byte is a character, so this cannot fail. Only comments and
        # descriptions carry the bytes UTF-8 rejected, and the numbers are ASCII either way.
        text = bytes.get_string_from_ascii()
    return text


## A line with its comment removed, trimmed. Empty when the line was only a comment.
static func strip_comment(line: String) -> String:
    var out: String = line
    for marker: String in ["//", "#", ";"]:
        var at: int = out.find(marker)
        if at >= 0:
            out = out.substr(0, at)
    return out.strip_edges()


## A comma-separated triple, as a vector. Upstream writes these space-separated in some files and
## comma-separated in others, so both are accepted.
static func vector3(value: String) -> Vector3:
    var parts: PackedStringArray = value.replace(",", " ").split(" ", false)
    if parts.size() < 3:
        return Vector3.ZERO
    return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


## The fields of a comma-separated line, trimmed.
static func fields(line: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for part: String in line.split(","):
        out.append(part.strip_edges())
    return out
