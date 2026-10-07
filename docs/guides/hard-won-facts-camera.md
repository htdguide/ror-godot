# Hard-won facts: the camera, its exposure and its lens

Audience: anyone changing a camera preset, the exposure a weather preset is metered at, or the
depth of field. Split out of `hard-won-facts-light.md` when that file reached the project's
400-line cap; the camera is its own subject, and these are about what the three numbers on a lens
do rather than about what is in front of it.

See `hard-won-facts-light.md` for skies, colour and anything that measures a frame, and
`hard-won-facts-materials.md` for what a surface's own shader does.

- **The ambient term is exposed twice, and the comment saying it is not is wrong.**
  `BlockoutWorld` pre-multiplies `ambient_light_energy` by the camera's own exposure scale, on the
  stated grounds that Godot's normalisation reaches physical lights and not the ambient — recorded
  from a measurement where a surface lit only by `ambient_light_color` photographed identically
  across three stops. Measured again from the other direction, that conclusion does not hold. Under
  `noon_clear`, opening one stop by aperture, by shutter or by film each multiplies a sunlit grey
  patch by 2.1623 rather than 2; half a stop gives 1.4673 against 1.4142 and two stops 4.9135
  against 4. One model fits all three: `(1 - f) * E + f * E^2` with `f` about 0.081, so roughly
  eight per cent of the light in that frame goes as the *square* of the exposure. Lit by a single
  directional light with no sky at all, the same three controls read 2.0000, 2.0000 and 2.0000, so
  the lens itself is exact and what is doubled is the ambient. `one_stop_is_one_stop` holds the
  exact half; putting a sky back into its scene is how the fix gets checked. **Do not simply delete
  the pre-multiplication** — the original measurement was real, and whatever it was measuring needs
  explaining before the balance of every lighting gate here is moved.

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
