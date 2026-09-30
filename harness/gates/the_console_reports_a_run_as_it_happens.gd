extends GateBase
## A suite run reports each gate to the console as it finishes, not in a summary at the end.
##
## A full run is minutes long. A console that shows nothing until it is over is, for the person
## watching it, a console that shows nothing — and the reason to run gates from a window at all
## is to see what is happening while it happens.
##
## The claim has a timing in it, which is the part worth checking: the reports have to arrive
## **before the command returns**, one per gate, in the order the gates ran. A front end that
## collected them and printed them at the end would satisfy a count and fail the purpose, so the
## count is taken while the command is still running.
##
## The agent's channel deliberately does not get these — it gets one line for the whole command
## however many gates it ran. Progress a person wants to watch and progress an agent pays for
## are different things, and `ConsoleTable.progress` is the seam. That is checked here too: a
## run that reported every gate into the agent's channel would be a regression in the thing D0
## spent its line budget on.

## Gates to run inside this one. Cheap, no GPU, no world: what is being measured is the
## reporting, and a slow subject would only make the gate slow.
const INNER: Array[String] = ["gate_metadata", "static_state"]


static func meta() -> Dictionary:
    return {
        "name": "the_console_reports_a_run_as_it_happens",
        "proves": "running gates from the console reports each one as it finishes, in order and before the command returns, without adding lines to the agent's channel",
        "builds_on": ["console_fronts_agree"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "%d reports, one per gate, all arrived before the command returned; the agent's"
            % INNER.size() + " channel still gets one line for the whole command"
        ),
        "why": (
            "a suite run is minutes long and a summary at the end of it tells a person nothing"
            + " while they wait. The timing is the claim: a front end that collected the"
            + " reports and printed them at the end would pass a count and fail the purpose."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "D0",
    }


func run(harness: Node) -> Dictionary:
    var table: ConsoleTable = ConsoleTable.new(harness)
    var seen: Array[String] = []
    table.progress.connect(func(text: String, _ok: bool) -> void: seen.append(text))

    # The inner run opens and closes containers of its own and leaves the harness pointing at
    # none, which would strand the container this gate is itself running in. Saved and restored
    # rather than worked around: a gate that runs gates is a legitimate thing to do and the
    # harness should come back the way it was found.
    var outer_container: GateContainer = harness.container
    var outer_terrain: TerrainWorld = harness.terrain

    var during: int = -1
    var line: String = "gate run %s" % " ".join(INNER)
    var result: Dictionary = await table.dispatch(line)
    during = seen.size()

    harness.container = outer_container
    harness.terrain = outer_terrain

    if not (result.get("ok", false) as bool):
        return fail("the inner run failed: %s" % result.get("detail", ""))
    if during != INNER.size():
        return fail(
            "%d gates ran and %d were reported by the time the command returned: the console is"
            % [INNER.size(), during] + " not seeing the run as it happens",
            during
        )
    for index: int in INNER.size():
        if not seen[index].contains(INNER[index]):
            return fail(
                "report %d is '%s' where gate %d was %s: the reports are out of order"
                % [index + 1, seen[index].strip_edges(), index + 1, INNER[index]]
            )
        if not seen[index].contains("PASS") and not seen[index].contains("FAIL"):
            return fail("report %d carries no verdict: '%s'" % [index + 1, seen[index]])

    # And the agent's side is still one line for the whole command, however many gates it ran.
    var agent_line: String = ConsoleResult.to_line(1, line, result, 1.0)
    if agent_line.contains("\n"):
        return fail("the agent's reply to one command is more than one line")
    # Only what the line *answers* with. `cmd` echoes the command, so it names the gates by
    # definition — checking the whole line for them says the reply leaked progress when it did
    # nothing of the kind, which is what the first version of this check did.
    var parsed: Variant = JSON.parse_string(agent_line)
    if parsed == null or not (parsed is Dictionary):
        return fail("the agent's reply is not JSON: %s" % agent_line.substr(0, 120))
    var answered: String = "%s %s" % [
        (parsed as Dictionary).get("detail", ""),
        JSON.stringify((parsed as Dictionary).get("data")),
    ]
    var reported_gates: int = 0
    for name: String in INNER:
        if answered.contains(name):
            reported_gates += 1
    if reported_gates > 0:
        return fail(
            "the agent's reply names %d of the gates that ran: per-gate progress has leaked"
            % reported_gates + " into the channel, which is charged by the line"
        )
    return ok(
        "%d gates reported to the console as they finished, in order, before the command"
        % during + " returned; the agent's reply stayed one line of %d bytes"
        % agent_line.to_utf8_buffer().size(),
        during
    )
