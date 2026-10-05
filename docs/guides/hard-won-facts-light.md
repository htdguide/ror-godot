# Hard-won facts: light, colour and capture

Audience: anyone changing the renderer's lighting, its colour handling, or any gate that measures
a picture. Split out of `hard-won-facts.md` when that file hit the project's 400-line cap; these
are one subject and they are the subject this project has been wrong about most often.

Almost every entry here began as a confident measurement that turned out to be of the wrong thing.
The pattern is consistent enough to state outright: **before believing a number about light, prove
the instrument.** A photographed step wedge, an exposure bracket and a negative control cost one
afternoon between them and have overturned four separate conclusions recorded below.

See `hard-won-facts.md` for the solver, the file formats, the terrain and the gate discipline.
- **"The terrain takes a smaller share of its light from the sky than anything standing on it"
  was never true.** It stood in this project's docs for a long time, measured at 21%, then 13.6%,
  then 111%, then 22.6%, moving with whatever else had changed — and it was a roughness mismatch
  inside `terrain_takes_the_light` itself. Its reference patch used
  `TerrainWorld.COLOUR_MAP_ROUGHNESS`, 0.6, which is *one term* of Terrain3D's roughness
  (`(color_map.a - 0.5) * 2 + normal_rough.a` plus a per-asset modifier) and not the result. The
  per-asset modifier is `RorTerrainSkin.ROUGHNESS`, 0.9. A smoother patch takes more of its light
  from the sky's specular than rougher ground does, so the gate was comparing two different
  materials and calling the difference a property of the ground. **Matched, they agree to 0.0%.**
  A comparison gate is only as good as the sameness of the two things it compares, and "same
  albedo" is not the same as "same material".
- **Godot's sky ambient does not follow the sun within a capture.** `daylight_shadows_are_readable`
  took its shaded sample by swinging the sun 180°, which with a `PhysicalSkyMaterial` drags the
  atmosphere below the horizon and measures night rather than shade. Replacing that with
  `sky_mode = SKY_ONLY` — same sun, same sky, direct light off — gave a **bit-identical** result,
  which is the interesting part: the ambient did not change when the sun moved, though it does
  change with turbidity. The radiance map that feeds `ambient_light_sky_contribution` is not
  regenerated per frame at `Sky.PROCESS_MODE_AUTOMATIC`. The method was wrong in principle and
  right by accident; it is correct by construction now.
- **A physically-proportioned daylight ratio and this project's shadow gates are in direct
  conflict, and it is a design decision rather than a bug.** Calibrating the sky to a measured
  10.7:1 sun-to-sky (against clear daylight's 10:1 to 18:1) cannot simultaneously satisfy
  `shadows_are_not_black`'s floor of 0.085 displayed shadow *and* its ceiling of 4x displayed
  sunlit-to-shadow — except by compressing highlights so hard that the image goes flat, which is
  what exposure 3.4 did. Removing the fill light makes it worse: shadows fall to 0.0221. The
  gate's own reasoning cites print holding about 1:8, so its 4x is stricter than the figure it
  argues from. **Nothing here was changed to resolve it.**
- **Photograph a step wedge, not a grey card.** Six patches a stop apart found two faults in one
  run that a single mid-grey patch could not have shown, because both were *additive* and an
  offset bends a measurement most where the subject is darkest. The brightest patch was 1% high
  and the darkest 9% high — one patch anywhere on that wedge would have read "about right".
- **`use_measurement_environment` was never dark.** It set the ambient colour to black and the
  ambient energy to zero and left `ambient_light_sky_contribution` at 1.0 — and at 1.0 the ambient
  comes from the sky whatever the colour says. It also left **fog** on, which adds a constant to
  every pixel in the frame. Every gate that ever measured something "in the dark" had both. Both
  are off now, along with `reflected_light_source`.
- **With the room actually dark, the lighting path is exact.** A photographed wedge is linear in
  reflectance to **0.00%**, doubling a light is a factor of two to **0.00%**, and a two-light
  ratio measures 6.80:1 against 6.80:1. So nothing is wrong with the renderer's lights or with
  the capture — which places the remaining sun-to-sky puzzle squarely in the **sky ambient**
  path, and nowhere else.
- **Lambert's cosine law will correct your expectation before it corrects the renderer.** The
  lighting-ratio check first compared a photograph against 20000/5000 = 4:1 and the photograph
  said 6.80:1 — a 70% error that was entirely the gate's. The fill arrives at 54 degrees, so
  cos(54) = 0.588 of it lands and 20000 / (5000 x 0.588) is 6.80 exactly. A photographer aims an
  incident meter at the camera for the same reason.
- **A capture can carry light, and it takes one flag.** `SubViewport.use_hdr_2d` makes the
  viewport texture `FORMAT_RGBAH` and linear, so values above white survive: an unshaded quad at
  albedo 4.0 reads 25.312 through it and 1.000 without it. 25.312 is `srgb_to_linear(4.0)`, which
  is also the reminder that `StandardMaterial3D.albedo_color` is sRGB on the way in — to inject a
  known linear value you need a shader uniform straight into `ALBEDO`, not a material colour.
  `Image.save_exr` then writes it. `captures_carry_real_light` calibrates the path end to end:
  0.25, 0.75, 2.0 and 8.0 read back within 0.24%.
- **Calibrating the instrument did not settle the sun-to-sky question, and that is itself the
  finding.** Measured through the HDR capture the ratio is **6.4:1** — the first trustworthy
  figure — but it still moves with exposure: 6.4:1 at ISO 32, 2.7:1 at 64, 19.2:1 at 16, on one
  unchanged scene, with a capture proven linear to 0.24% up to a value of 8. A gain cannot change
  a ratio, so the non-linearity is in the *render*, not the capture. The suspicion is that under
  physical light units the sky's ambient contribution and the direct light do not share an
  exposure normalisation. **Two instruments have now been wrong in a row on this question; the
  lesson is to calibrate before measuring, not after being surprised.**
- **A ratio read off an 8-bit PNG is not a ratio of light, and it cannot be fixed by dividing.**
  `daylight_shadows_are_readable` reads its "scene-referred" samples out of a captured PNG, which
  is 8-bit and display-encoded. Turning on physical light units exposed it: the *same scene* gave
  1.3:1 at ISO 100, 3.4:1 at 25, 12.2:1 at 12 and 38.6:1 at 6. **A gain cannot change a ratio**,
  so the measurement is not linear — the sunlit sample saturates at the top and the shaded one
  quantises toward zero at the bottom, and only a narrow exposure window is valid at all. Undoing
  the sRGB transfer does not rescue it (1.8, 3.6, 9.4, 28.8 across the same sweep). **Every
  sun-to-sky figure this project has recorded came from this measurement** — 3:1, 4:1, 10.7:1 —
  and none of them is a light ratio. Measuring a 10:1 scene needs an HDR capture path; until there
  is one, no number from this gate should be compared against a physical illuminance figure.
- **Physical light units do not make the exposure fall out for free.** With
  `use_physical_light_units`, the sun at 100 klx and `CameraAttributesPhysical` doing the
  exposure, the ISO still ended up being chosen by a *shadow* gate rather than by the sun: above
  ISO 40 La Paz's pale ground bleaches, below 32 the shadow drops under
  `shadows_are_not_black`'s 0.085 floor, and the window between them is half a stop wide. The
  gates' thresholds were calibrated when the scene was brighter than daylight, and they now bound
  the exposure from both sides.
- **A fill light cannot lift a shadow it is itself shadowed by.** Raising `FILL_LUX` from 6 000 to
  20 000 moved the measured shadow from 0.0479 to 0.0578 against a floor of 0.085 — a three-fold
  increase buying a fifth of what was needed, because the fill casts shadows too and the region
  being measured is in both. Exposure is what moves a shadow floor; a fill moves the sides.
- **A config flag can claim a thing the code does not do, and nothing will catch it.**
  `weather_cfg.gd` carried `physical_sky: true` for every daylight preset while `_build_sky`
  built a two-colour `ProceduralSkyMaterial` gradient. No gate could see it: every lighting gate
  was graded against whatever sky was actually being built, so the name being a lie cost nothing
  and was invisible until somebody read both files. A flag named after a technique is worth
  checking against the technique.
- **An atmosphere model is dimmer than a gradient tuned to look right, and that is the point.**
  Switching the clear presets to `PhysicalSkyMaterial` moved sun-to-sky from 3.2:1 to 4.1:1 —
  toward clear daylight's ~14:1 — and darkened the whole frame, so
  `daylight_shadows_are_readable` failed on its own readability floor with exactly the right
  diagnosis: *"the light is there and the grading is burying it."* Exposure is the control for
  that, and it went 0.7 to 1.05 to put the displayed shaded surface back at 0.066 where it had
  been. Fixing it with sky energy instead would have undone the ratio it was meant to improve.
- **A sky's energy is not in the lux a light is stated in.** `DirectionalLight3D.light_intensity_lux`
  takes its value literally under physical light units; a sky's `energy_multiplier` never goes
  through that conversion. Measured against a key light of stated lux in a dark room, one unit of
  uniform sky radiance delivers **98,325.74 lx** to a facing surface — reproducible to ten
  significant digits, invariant to the sky's radiance over a 16x range, to the panorama's
  resolution (16x8 and 256x128 agree exactly) and to the radiance map's size. It sits 1.70% under
  1e5 and that gap is unexplained. So a sky left at `energy_multiplier = 1.0` is worth roughly as
  much illuminance as the noon sun, which is why no amount of turning the sun up or the turbidity
  down ever brought the sun-to-sky balance near clear daylight's figure.
- **Sky ambient *is* exposed like a light.** One stop gains a key light by 2.0000x and a uniform
  sky by 2.0000x, 0.00% apart. The exposure-dependent sun-to-sky ratio that prompted four rounds
  of measurement — 6.4:1 at ISO 32, 2.7:1 at 64, 19.2:1 at 16 — was the old uncalibrated
  instrument, fog and leaked sky ambient, and not the sky path at all.
- **Under physical light units a light has a colour temperature, and no temperature is neutral.**
  `Light3D.light_temperature` defaults to 6500 K and photographs as (1.0, 0.9419, 0.9919) once the
  brightest channel is normalised — a 6% green deficit, constant across a thirty-fold brightness
  range, on top of whatever `light_color` says. Sweeping the temperature moves the cast but never
  through neutral: measured at 5000 K it is (1.0, 0.790, 0.629) and at 9000 K (0.674, 0.741, 1.0),
  and red-equals-blue and green-equals-red cross at different temperatures. The cause is which
  locus the conversion walks: 6500 K on the Planckian locus sits below the daylight locus that
  sRGB's white point is on. So every light in this project carries a slight cast, and a colour
  measurement has to white balance off a known patch rather than assume the light is white.
- **A colour measurement cannot go through a luminance.** A channel swap, a doubled transfer
  function or a tinted tonemapper all leave luminance plausible, so every luma-based gate in this
  suite is blind to them by construction. Measured: swapping red and blue in the chart shader
  costs 113 delta E on the worst patch and 41.5 on average while a luminance reading barely moves.
- **White balancing off a reference patch buys accuracy and costs a whole fault class.** It is the
  only honest way to measure colour under a light that is not neutral, and it makes a tinted light
  undetectable — measured, a green light at (0.8, 1.0, 0.8) leaves the chart gate green at 0.029
  delta E. Three degrees of freedom spent on the white card still leaves fifty-four values and the
  six published grey luminances to predict, so the method is not weak; it is specifically blind.
- **A `Sky` left at its default `process_mode` does not render the same picture twice.** The
  radiance map is approximated across frames, and anything rough enough to take its specular from
  that map inherits the approximation: measured on the hero truck's drop, a band of distant ground
  alternated between 0.6703 and 0.9906 luminance on alternate frames — the far half of the checker
  washing to pure white and back — with the camera bolted down and the truck long since at rest.
  Two discrete values flipping, not noise. `Sky.PROCESS_MODE_QUALITY` fixes it and the band then
  holds to 0.000000. Grazing angles take it worst, which is why it was the distance that flickered.
- **A clipping test cannot be a count of pixels near white.** A big smooth sky crosses 1.0
  somewhere and the band of pixels near the crossing is as wide as the gradient is shallow:
  measured, 0.356% of samples landed within 0.002 of white in a frame that is not clamped at all.
  What distinguishes a clamp is the *shape* — compare the histogram bin at white against the bin
  immediately below it. A gradient fills both about equally (2459 against 2012); a clamp empties
  the lower one into the upper.
- **Requiring a fixed margin above white grades the weather, not the buffer.** A headroom gate
  first demanded the brightest pixel reach 2.0 and failed golden dusk at 1.205 — which is a scene
  eight stops dimmer at a fixed exposure, not a buffer running out of range. The honest test is
  "strictly above white", since a display-referred buffer cannot exceed it at all.
- **A gate that photographs a highlight has to have one in frame.** The same gate first framed the
  hero truck, peaked at 1.376, and read that as missing headroom. There was no sun in the shot:
  the brightest thing in a three-quarter view of a truck is the sky. Aim at the light the preset
  actually places rather than lowering the threshold to fit the picture that missed it.
- **A `ReflectionProbe` lights everything inside its box, not just the object it was added for.**
  `ActorProbe` gave each vehicle a probe sized to the bodywork plus a 1.5 m margin, so the probe
  claimed a ring of road and lit it from a capture taken once, when the vehicle was built. Cycling
  the weather left that road holding daylight while everything outside the box went blue: a hard,
  world-axis-aligned rectangle around the truck, reported twice from the window. Measured on a
  uniform test road, 403.8% colour difference between road inside the box and open road.
- **A probe's box is its influence; `max_distance` is its capture.** The 1.5 m margin existed "so
  the probe captures the ground under the vehicle", which is not what the box does. Shrinking the
  box to 0.2 m keeps every ground reflection — capture range is unchanged — and takes the road
  difference to 4.5%. A gate had encoded the same confusion and demanded the larger margin.
- **The probe's ambient term is the larger half of that fault, and `intensity` does not touch it.**
  `ambient_mode` defaults to contributing ambient light, frozen with the capture. Disabling it
  alone took 403.8% to 135.1%. Setting the probe's intensity to zero — the probe contributing no
  visible reflection at all — still measured 243.4%, because intensity scales the reflection and
  not the ambient. A probe that is "off" can still be lighting the scene.
- **Comparing one surface under two lights needs one pixel mask.** `body_blocks_sun` averaged each
  frame over its own above-floor pixels, so the darker frame's mean was taken over only its
  brightest survivors and the ratio was pulled towards one. It had been reporting 1.18 against a
  1.25 bar; with the lit frame's mask applied to both, the same scene reads 8.93. A segmentation
  that moves with the thing being measured is not a measurement.

- **The daylight locus is published and this project now carries it.** Godot's `light_temperature`
  walks the Planckian locus; sRGB's white point is D65, which is on the daylight locus, a
  different curve fitted to measured skylight. `DaylightLocus` is CIE 15's cubic in 1/T with the
  tabulated D50, D55, D65 and D75 chromaticities beside it, and
  `the_daylight_locus_is_where_the_books_put_it` holds the formula to those four published values:
  worst 0.000126, at D75.
- **A gate written to prove a remembered number failed, and the number was wrong.** The D series
  was named when the second radiation constant was 1.4380e-2 m K and it is 1.4388e-2 now, so D65
  is 6503.6 K rather than 6500 — and this was written down earlier as putting x out by 0.0008. The
  real figure is 0.00007: the correction halves an already small residual, from 0.000196 to
  0.000126, and both are inside any tolerance worth setting. The first draft of the gate *required*
  the correction to matter and failed on its own claim. It reports both distances now and turns on
  neither, because a bound drawn between them would be a bound drawn around the answer.

- **Under physical light units, the exposure is part of the hour and not of the camera.** An
  hour states its light in lux — a hundred thousand for midday sun, a quarter of one for a full
  moon — so it has to state the aperture, shutter and sensitivity that light was metered for. A
  camera set for noon sees nothing at all by moonlight, and no lamp can reach it: a 22,000 cd low
  beam puts about fifty lux on the road at twenty metres, a two-thousandth of what a daylight
  exposure expects. Reported from a window as "during the night headlights are not working";
  the headlights were working. `night_moon` opens the lens to f/2.8, a sixtieth and ISO 1600,
  which is 850 times a midday exposure, and `PhysicalCamera.reexpose` re-meters when the weather
  changes.
- **`ambient_light_energy` does nothing while the sky supplies all of the ambient.** Godot blends
  the sky's own irradiance against `ambient_light_color * ambient_light_energy` by
  `ambient_light_sky_contribution`, and at 1.0 the colour and the energy are both ignored.
  Measured, 0.05 and 0.015 gave the same frame to four decimals. A preset that wants a dark
  ground under a sky it can still see has to drop the contribution and light the ground from the
  colour.
- **Godot takes a lamp's output in lumens and defaults it to a thousand.** A ceiling fitting. A
  tail light is about twelve lumens, an indicator forty, a reversing lamp a hundred; ten omni
  lights at the default lit the whole vehicle like a showroom the moment the switch went on,
  which is invisible at a daylight exposure and is the entire picture at night.
- **A spot light's projector is only sampled when that light casts a shadow.** The beam pattern —
  the cut-off, the hot spot, the kerb-side step — is a texture the lamp is seen through, and with
  `shadow_enabled` false the lamp emits nothing whatever: measured, the road ahead read 0.2150
  with a quarter of a million lumens pointed at it and 0.2150 with the lamps off, the same frame
  to four decimals. Upstream turns headlight shadows off, and this project cannot.
- **A float image with a generated mip chain is not a usable projector.** `FORMAT_RGBAF` plus
  `generate_mipmaps` sampled as black. Eight bits, no mipmaps.
- **`f` means headlight and modders use it for lamps that are not.** The hero truck's rear lights
  are two `f` rows with a red flare material on them, which built two white 150 m beams firing
  out of the tailgate. A lamp only gets a beam if it faces the way the vehicle goes, which the
  actor's own frame knows: forward is -Z there, because upstream's `cameras` section names a node
  behind the centre.
- **A sky shader has to apply the hour's energy to everything it draws, clouds included.** The
  marched cloud layer was mixed over the gradient *after* the energy multiplier, so a night that
  states four ten-thousandths dimmed the gradient and left the clouds at their daylight
  brightness: a blazing white overcast with black holes in it, and a vehicle whose reflection
  probe caught it and turned white.
- **A reflection probe on `UPDATE_ONCE` holds the sky it was built under.** Switching a window
  from noon to night leaves the bodywork reflecting a daylight sky. Re-assigning `update_mode`
  marks it dirty and it takes the hour it is actually in.
- **A spot light's projector is a square image and a beam is not square.** The light samples the
  whole texture, corners included, so a pattern with light at its edge is thrown as a rectangle
  with hard sides — reported from a window as "a weird shape how it lights", and it was the
  texture's own border drawn on the road. The pattern has to fall to nothing inside a circle.
- **A measurement preset is an instrument, not an hour of the day.** `spike_black` is an unlit
  void so that a gate can encode a number into a pixel and read it back; a window that cycles
  into it finds a black world with headlights that appear not to work. It carries
  `measurement: true` and the window leaves it out.
- **A cloud shader does not know the sun has set.** The marched layer takes its colour from a
  stated cloud colour and a Beer's-law shadow, neither of which has the hour in it, so a moonlit
  sky kept daylight-white clouds — ten times the clear sky beside them, which at midnight is a
  band of grey noise standing over a black world. `cloud_light` is how much light is falling on
  them.
- **A disc and a star are lights in front of the sky, not part of its brightness.** Scaled by the
  sky's own four-ten-thousandth night multiplier, the moon is not dim, it is absent. They carry
  their own `disc_energy` and star brightness and are added after that multiplier.
- **An unlit surface does not know what time it is.** A terrain paints its horizon on one — La
  Paz's backdrop is a photograph of mountains with the daylight already in it — and under a day
  that moves it is the one thing that does not: at midnight the world goes black and a band of
  bright mountains stays up around it. Nothing can light a picture of being lit, so
  `BlockoutWorld.dim_unlit` scales them by how much of the day it is, and a lamp's lens says
  `keeps_its_own_light` to opt out.
- **Under physical light units the exposure belongs to the hour.** `DayCycle` states the three
  numbers along with the lux: f/8, a hundred-and-twenty-fifth and ISO 32 at noon; f/2.8, a
  sixtieth and ISO 1600 under a quarter-lux moon. Interpolated in ratios rather than in steps,
  because a sky that runs from 0.0004 to 1.0 linearly is full daylight for all but the last
  moments of dusk.
- **How bright an hour is and what colour it is are two different questions.** The warmth of a low
  sun was computed from the same number as its brightness — `low * day * (1 - day) * 4`, which is
  zero wherever the brightness has settled — so the only warm frames in a day were the two
  half-hours when it happened to be halfway, and seven in the morning was a pale blue-white noon
  with the sun 16 degrees up. Twilight is about fifteen degrees of elevation wide; the golden hour
  is nearer thirty, and it has to be its own curve.
- **A cloud is the colour of whatever is lighting it.** Mixing the light's colour in at half
  strength left a white overcast over an orange sunrise, which was most of what read as "weirdly
  white". At 0.85 the clouds take the hour.
- **A star has to be a point inside its cell, not the cell.** Quantising the view direction and
  lighting the whole cell draws square stars; keeping a jittered position per cell and fading with
  the angular distance to it draws round ones for the same cost.
- **Ambient occlusion darkens the ambient term and nothing else.** It is the right name for "the
  moon should not reach the inside of the bed" and it is not the whole of the fault: at twelve
  times its own strength, Godot's SSAO moved an enclosed truck bed from 0.0343 to 0.0320. What
  lights an enclosed surface is *reflection* — the sky's radiance, and above all a reflection
  probe.
- **A reflection probe cannot know what is in front of a surface.** It is one cubemap taken from
  the middle of the actor and applied to everything inside its box, so the floor of a truck bed
  reflects the sky that the bed's own sides are blocking. Measured at dusk: bed 0.0626 against a
  roof of 0.0671 — 93% — and with the probe off, 0.0305 against 0.0616. The probe is a daylight
  nicety and now follows the hour down.
- **A shadow that lets a quarter of the light through is a daylight device.** `SHADOW_OPACITY` is
  0.72 because by day the sky fills a shadow; at night nothing does, and the moon shines through
  whatever is standing in front of it. The day cycle runs it to 1.0 after dark.
