# Hard-won facts: the camera, its exposure and its lens

Audience: anyone changing a camera preset, the exposure a weather preset is metered at, or the
depth of field. Split out of `hard-won-facts-light.md` when that file reached the project's
400-line cap; the camera is its own subject, and these are about what the three numbers on a lens
do rather than about what is in front of it.

See `hard-won-facts-light.md` for skies, colour and anything that measures a frame, and
`hard-won-facts-materials.md` for what a surface's own shader does.

- **Where a light comes from decides whether the camera's exposure reaches it, and the two cases
  are opposite.** Measured directly, a grey patch lit by nothing else, read across three stops:

      a stated `ambient_light_color`   1.000x per stop — the exposure does not reach it at all
      a sky's own irradiance           4.148x per stop, 16.760x for two — reached twice

  Both of this project's apparently conflicting measurements were right about their own case. A
  stated ambient colour is not normalised, which is why `BlockoutWorld` pre-multiplies
  `ambient_light_energy` by the camera itself — that compensation is correct and should stay. A
  sky's light is normalised twice, which is why this project's own sky shader divides by
  `light_exposure` in the cubemap pass; a plain `ProceduralSkyMaterial` does not and shows the full
  square.

- **A camera that changes after the world was built has to re-meter the sky with it.** The
  cancellation above is a number baked into the sky material, so a camera moved afterwards leaves it
  stale: the sky's share of the frame is then exposed once by the old number and once by the new.
  Measured on a sunlit patch under `noon_clear`, one stop came out at 2.1623 instead of 2, half a
  stop at 1.4673 and two stops at 4.9135 — a frame with about 8% of its light exposed twice. One
  call to `WorldSky.reexpose` and the same three controls read 2.0084. `one_stop_is_one_stop` holds
  it; the first draft of that gate had this bug and reported it as a fault in the renderer.

- **Depth of field is off until a focus distance is set, and then it is weaker than the lens says.**
  Nothing blurs while `CameraAttributesPhysical.frustum_focus_distance` is unset — a row of posts
  from three to forty-eight metres came back uniformly sharp through an f/1.8 85 mm lens — so DOF is
  opt-in per camera preset (`focus_m`), and every gate written against a pinhole camera keeps one.
  With it set the blur is real and grows with distance, and it is **far smaller than the thin-lens
  formula gives**: measured as the 25–75% width of an edge at 1080 lines, 85 mm at f/1.8 focused at
  4 m read 2, 9 and 11 px at 8, 16 and 32 m where `C = f^2|S2-S1| / (N S2 (S1-f))` on the camera's
  own 24 mm sensor gives 23, 35 and 40. The shortfall is not a constant factor, so it is not simply
  the shape constant of an edge measurement. **Unfinished rather than concluded**: Godot's bokeh is
  a hexagon at medium quality and the relation between an edge's transition width and that kernel's
  size was never established, so this is a measurement method that needs validating before the
  engine can be said to disagree with optics. `harness/dev/dof_probe.gd` is the instrument.
