# Human sessions

Audience: contributors, and the person being handed the controls.

Automated gates catch regressions. They do not say whether the game looks good or drives
right. Every milestone with anything human-testable therefore ends with a session where
a person drives it, and no such milestone is closed by the agent.

## Running one

    tools/play.sh
    tools/play.sh --shot diag_grid_wide
    tools/play.sh --weather golden_dusk

The window is tracked while it lives and untracked when it closes, so
`tools/windows.sh list` always tells the truth about what is open.

## The rules

1. The agent may not mark a human-gated milestone complete. Green gates are what earns
   the right to ask, not a substitute for the answer.
2. The session is launched by one command. Hand-assembled arguments are how two sessions
   end up testing different things.
3. Everything reported in a session becomes either a new automated gate or a named
   deferred item before the milestone closes. Verbal findings that evaporate are the
   failure mode this process exists to prevent.
4. A session where nothing was found is still a pass, and is recorded as one.

## What gets asked at each milestone

Recorded in the plan (`docs/PLAN.md`, §3.6). In short: M1 is about whether it drives and
whether the deformation feels like Rigs of Rods; M2 about whether the scene looks good;
M2b about camera and grain, which are taste; M3 about smear at speed; M5 about night
headlights; M6 about wetness timing; M7 about particle density.

Human attention is the scarce resource. Spend it on finding new problems — once a
problem is found, it becomes a replay gate and is never re-checked by hand.
