class_name ConsoleResult
extends RefCounted
## What every command returns, and the only shape either front end renders.
##
## **Token efficiency is a design constraint here, not a nicety.** The agent pays for every line
## it reads back, so a result is one line: whether it worked, how long it took, and one sentence.
## Anything large — an image, a capture, a heightfield, a gate's artifact — is written to a file
## and the result carries the *path*. A command that returns a frame instead of a path is a
## command that costs the agent a thousand tokens to learn one number.

## A command that did what it was asked. `detail` is one line, and it is what a person reads.
static func ok(detail: String, data: Variant = null, artifact: String = "") -> Dictionary:
    return {"ok": true, "detail": detail, "data": data, "artifact": artifact}


## A command that could not. `detail` says what would have to change.
static func err(detail: String) -> Dictionary:
    return {"ok": false, "detail": detail, "data": null, "artifact": ""}


## One JSONL line for the agent's channel: the result, plus what was asked and how long it took.
##
## `data` is included only when it is small. A command that wants to hand back something big
## writes a file and sets `artifact`, and the agent reads the file if it needs to — which is the
## difference between a result costing one line and costing a frame.
static func to_line(seq: int, command: String, result: Dictionary, elapsed_ms: float) -> String:
    var row: Dictionary = {
        "seq": seq,
        "cmd": command,
        "ok": result.get("ok", false),
        "ms": snappedf(elapsed_ms, 0.1),
        "detail": result.get("detail", ""),
    }
    var artifact: String = result.get("artifact", "") as String
    if artifact != "":
        row["artifact"] = artifact
    var data: Variant = result.get("data")
    if data != null and JSON.stringify(data).length() <= MAX_INLINE_DATA:
        row["data"] = data
    return JSON.stringify(row)


## How much structured data may ride along in the line before it has to become a file instead.
## A gate's numbers fit; a frame does not, and the point is that it cannot try.
const MAX_INLINE_DATA: int = 512
