# Human tests

Audience: the owner, running a session of window tests; and the agent, keeping this list current.

Everything below is proved against upstream by a gate, but nobody has looked at it in a window.
The gates check the arithmetic; only a person can say whether it looks and feels right. Work
through it in one session, write the verdict next to each item, and move the passed ones to the
bottom.

Each item says how to open it, what to do, and what right looks like. Commands run from the
repository root. On a Mac the airplane and boat pad (right edge of the window) stands in for Home,
PgUp and PgDn; press Esc first to free the mouse. Where an item names a corpus file, any other file
with the same section works too.

Collected 2026-10-14, after the boats commit (`ff1f897`).

## Aircraft

Open: `tools/play.sh --vehicle "assets/corpus/181_supermarine-spitfire:spitfire_Vb.airplane"`

1. **Flaps lower.** 1/2 (or Flaps -/+): the flap panels under the wings move down a step at a time,
   Ctrl+1/Ctrl+2 none and full. (`the_animator_is_upstreams`; before this they never moved.)
2. **A first flight.** Engines on/off, Full throttle, hold Stick back at speed. It should lift off,
   climb, bank with the ailerons and turn with the rudder, and stall if pulled too hard. You are
   the judge of whether it flies like Rigs of Rods. (`the_wing_is_upstreams`,
   `the_aero_engine_is_upstreams`)
3. **Autopilot.** Once climbing: WLV levels the wings; HDG holds the heading shown (HDG +/-); ALT
   holds the altitude shown (100 ft steps); V/S holds a climb rate; IAS moves the throttle to hold
   the airspeed. Lit buttons are the modes that are on. NAV turns itself off at once (no ILS yet).
   (`the_autopilot_is_upstreams`)
4. **Gauges.** Cockpit gauges that read the engine (rpm, throttle, torque, pitch, status), the
   flaps, the air brakes or the angle of attack move with them. Try any airplane with a cockpit.
5. **Wing panels.** The drawn wing panels sit on the wings, their control surfaces swing with the
   controls, and a broken wing disappears. (`a_wing_is_drawn_as_upstream_meshes_it`)
6. **Prop wash and engine kinds.** Turboprops, piston props and jets all pull; a jet's afterburner
   above 0.93 throttle; R reverses. Try `assets/corpus/200_soukhoi-su-37:45e43UID_SU-37.airplane`
   for jets.

Open: `tools/play.sh --vehicle "assets/corpus/1071_gavril-mz2-plane:gavrilmz2.airplane"`

7. **Air brakes.** 3/4 (or Air brakes -/+) open them a fifth at a time, Ctrl+3/Ctrl+4 none and
   full. The panels swing open on their hinge and the plane slows. (`an_air_brake_is_upstreams`)
   Also on the Concorde, Su-37, An-225 and 767 in the corpus.

## Boats

Open: `tools/play.sh --vehicle "assets/corpus/189_weasel-class-boat:780dUIDweasel.boat" --map starling-beach`
(the start is on the beach, 5 m from deep water: reverse off the sand if it is stuck)

8. **It floats.** The hull sits in the water at a sensible waterline, rocks and settles, and does
   not sink. (`a_boat_floats_as_upstreams`; the solver has not been seen taking a map's water in a
   window yet, only in a gate, so a boat sitting on the sea bed here is a real bug.)
9. **It drives.** Up/Down step the throttle, Left/Right move the rudder (it stays where you leave
   it), PgDn centres it, PgUp reverses. It pulls away, turns, and slows in the water.
   (`a_screw_prop_is_upstreams`)
10. **Boat gauges.** Rudder and throttle gauges or levers follow the controls.
11. **Other boats.** The Nordia Express ferry and the Gypsea jon boat
    (`assets/corpus/191_m-v-nordia-express`, `assets/corpus/193_gypsea-12-jon-boat-now-with-trailer`).

## Ground vehicles

The hero: `tools/play.sh --truck`. Keys are printed on start (and in the window's help).

12. **Cruise control** (Shift+Space; Ctrl+R faster, Ctrl+F slower, Ctrl+Space match): holds its
    speed up and down hills, lets go on the brake. (`cruise_control_holds_its_speed_as_upstreams`)
13. **Speed limiter.** `assets/corpus/1028_lotus-76-1:Lotus_F1_70s2.truck`: full throttle stops
    gaining at its limit. (`a_speed_limiter_holds_the_throttle_as_upstreams`)
14. **Traction control and ABS** (Shift+T, Shift+B): on the Lotus and on
    `assets/corpus/1001_el-brute:EL_BRUTE.truck`, wheelspin is held back and hard braking does not
    lock the wheels. (`a_cars_driving_aids_reach_its_wheels`)
15. **Differentials and transfer case** (V axle, J interaxle, T 2WD/4WD, Y range):
    `assets/corpus/1018_star-monster:PriceCrusherLF4.truck`. Locking changes how it climbs and
    turns; the differential panel shows what the solver has. (`differential_laws_are_upstreams`,
    `a_transfer_case_drives_its_second_axle_in_4wd`)
16. **Turbo.** `assets/corpus/1003_mkds-standard-kart:F3DMStandardKartTurbo.truck`: boost builds
    with rpm and the boost gauge reads it. (`the_turbo_is_upstreams`)
17. **Animated parts.** `assets/corpus/1001_el-brute:EL_BRUTE.truck`: gauges, levers and pistons
    that animators move follow the engine, the pedals and the gear lever.
    (`the_animator_is_upstreams`)
18. **Triggers.** `"assets/corpus/1009_mack-granite-truck-pack:Mack Granite crane.truck"`: beams
    that trigger commands, hooks or the engine do so when squeezed or stretched past their limits.
    (`the_trigger_is_upstreams`)
19. **Slide nodes and rails.** The kart (`F3DMStandardKart.truck`) and
    `"assets/corpus/1070_international-4400:International Durastar Box Truck Air.truck"`: parts
    on rails slide along them and stop at the ends. (`the_slide_node_is_upstreams`)
20. **Command rams.** The hero's doors open on 1-4, ramping by their inertia; rope rams (option r)
    pull and never push. (`a_ram_moves_by_its_rate_and_stops_at_its_bounds`,
    `a_command_key_ramps_by_its_inertia_curve`, `a_rope_ram_pulls_but_never_pushes`)
21. **Hooks and ropes** (L; Alt+L lets auto-locks go, Ctrl+L ropes): the crane's hook locks onto a
    load and reels it in; a rope rides on the nearest ropable.
    (`a_hook_locks_reels_in_and_lets_go`, `a_rope_rides_on_the_nearest_ropable`)
22. **Respawn with links.** Tie or hook a second vehicle (`--add`), then respawn yours: every link
    to it lets go. (`a_respawn_lets_go_of_every_link_to_it`)
23. **Detacher groups.** Crash a vehicle whose wheels are in detacher groups hard enough: the wheel
    comes off with its beams. (`a_detacher_group_takes_its_wheel_off`)
24. **Breakage.** Support beams break past their limit; only plain beams take a permanent bend;
    the cab survives as upstream's does. (`a_support_beam_breaks_past_its_limit`,
    `only_plain_beams_take_a_permanent_set`)
25. **Shocks2 and shocks3** feel like Rigs of Rods on a vehicle that uses them.
    (`shocks2_and_shocks3_are_upstreams_laws`)
26. **Modules.** `tools/play.sh --vehicle "assets/corpus/1018_star-monster:PriceCrusherLF4.truck@<module>"`
    builds the module named; the window lists the modules on load.

## Lamps and look

27. **Lamps.** Headlights, brake, reverse and indicator lamps follow upstream's switches (N, K, Z,
    C, X, Minus, F); blinkers blink at upstream's rate; dashboard lamps read the inputs their file
    names. (`a_lamp_lights_by_upstreams_switches_and_clock`)
28. **Spitfire body.** The fuselage and canopy hold together when the plane flexes (their binding
    was fixed: `a_forset_is_read_as_upstream_reads_it`).

## Several vehicles

29. **`--add`.** `tools/play.sh --truck --add assets/corpus/<dir>:<file>` puts undriven vehicles
    behind yours, in the same world; they collide with yours and with each other.
    (`an_added_vehicle_stands_behind_and_shares_the_world`)
30. **Split screen** (`--split`): two drivers, each on their own half of the keyboard.

## Known not in

Not for testing, listed so nobody files them: ILS approaches (terrain localizers are not read), the
ground-proximity warnings and every other sound, waves (upstream's are off by default), splashes,
ripples and other particles, trigger and animator beams are not drawn, the manual clutch.

## Already confirmed by the user

- Ties on the Tatra 815 with `EAGER_BEAVER_JEEP.load`: "It works" (2026-10-13).
- Airplane keys and the pad, with the highlight: "looks good" (2026-10-13).
- The Spitfire's rudder moving on Z and X, once hydros followed their flags: "now its fine"
  (2026-10-13).
- Wings drawn on the Spitfire (2026-10-13).
