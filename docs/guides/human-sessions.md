# Human sessions

Audience: contributors, and the person being handed the controls.

Automated gates catch regressions. They do not say whether the game looks good or drives
right. Every milestone with anything human-testable therefore ends with a session where
a person drives it, and no such milestone is closed by the agent.

## Running one

    tools/play.sh                         the main menu: start a game (vehicle, map, weather),
                                          graphics, quit — what the production build opens on
    tools/play.sh --truck                 the test park, driving
    tools/play.sh --truck --valley        Valley One instead
    tools/play.sh --shot diag_grid_wide
    tools/play.sh --weather golden_dusk

In the park: `F5` chase camera, `F6` free camera, `F7` the driver's seat. `L` lights, `Z`/`C`
indicators, `X` both off. `Esc` or `M` opens the settings panel — a row for every number a weather
states, refreshed to whatever preset or hour is chosen, so a preset can be read as well as seen —
which writes to the live scene and not to the project, so nothing has to be put back afterwards.

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

## Screenshots carry their own context

`P` in a session writes `artifacts/human/play-<stamp>-<n>.png` and a `.json` beside it with the
same name. The sidecar is for whoever has to act on the picture: a `summary` line to read at a
glance, then the camera's position, bearing, pitch, field of view and height above ground; the
surface underfoot by the terrain's own ground model; where the view ray meets the ground; the
vehicle and its HUD line; the frame's own fps, frame time, draw calls and primitives; and the
commit it was taken on.

The part that earns its place is **`in_frame`**: every object batch with an instance in the
frustum, sorted by how far off the centre of the frame it is, with how many instances and how far
away the nearest is. "That house has no texture" used to cost a round trip to establish which
house; the sidecar names it, because the thing being reported is almost always the thing nearest
the middle.

`a_screenshot_says_where_it_was_taken` holds it, against La Paz's own object files rather than
against anything recorded from a run. It found a real fault on its first pass: one mesh is one
batch per tile, so a map holds several sibling nodes with the same name, and Godot renames the
duplicates — the sidecar called a La Paz pole `@MultiMeshInstance3D@3`. The loader writes the file
name onto the node as metadata now, which the scene tree cannot rename.

## Photographing a model from every side

`tools/photoset.sh` does the hero vehicle; `tools/objectset.sh` does a terrain's own objects.

    tools/objectset.sh                          the six objects the map places most
    tools/objectset.sh --terrain-dir Russia     another terrain
    tools/objectset.sh --object store08.mesh    one object by name

Each object is built alone on the stage, framed from its own bounds, and photographed front,
back, left, right, top and three-quarter into one sheet per object under `artifacts/`. The gate
behind it fails any view that is **empty**, which is what a single-sided or inverted panel looks
like from outside.

That instrument did not exist until a window session reported walls visible from one side only,
and the suite had nothing to say: every building in the library was being drawn inside out,
because the mesh reader reverses a triangle for the vehicle path and a terrain object passes
through no such path. The measurement that settles *that* is a gate — the winding against the
normals the file carries — but what made it visible in the first place is a photograph from a
side nobody was taking.

It catches absent. It cannot catch a wrong texture or a wrong colour, which is why it produces a
sheet to look at rather than only a verdict.

### Painting the back of a face

`tools/objectset.sh` photographs with every surface dressed in `FacingPaint`: the front of a face
keeps its own texture, the back draws the axis it points along — red for x, green for y, blue for
z — unshaded, so the marker reads the same under any light.

**A culled back face is nothing, and nothing is not measurable.** A wall turned the wrong way
renders as empty sky, which is pixel for pixel what a correct empty sky looks like: the fault and
the absence of the fault are the same photograph. Painted, `haus3.mesh` is solid blue from the
left and green from above, and the sheet says which wall and which way it points.

Each view is labelled in the frame — FRONT, BACK, LEFT, RIGHT, TOP, 3 QUARTER — drawn as pixels,
because Godot's `Label` does not appear in a viewport capture and this build has no ffmpeg
`drawtext`.

**The gate reports and does not judge, deliberately.** Three bounds were tried and every one of
them separated nothing:

- *any paint is a fault* — a road slab is one sheet and from underneath you are correctly looking
  at its back;
- *paint on a closed object is a fault* — `road-slab.mesh` classifies as closed and paints 58% of
  its own top view, and no number says whether that is an inversion or a misclassification;
- *an empty view is a fault* — a cross-card tree is two vertical quads and from directly above it
  is edge-on and correctly shows nothing.

So the sheet carries the judgement and the gate carries the numbers. A reported measurement with
no verdict is worth more than a verdict nobody can defend.
