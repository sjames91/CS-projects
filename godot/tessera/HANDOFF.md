# Handoff: Tessera + Lower Orbit ship

Read this first if you're a new Claude session picking up this work.

## Where things are

- Branch: `ccr-815049d6-k4ed8z` (not merged into `main`, no PR yet).
- Editor: `godot/tessera/`. Open `project.godot` in Godot 4.3+ (Forward+,
  needs a Vulkan/Metal/D3D12 GPU). `README.md` lists every feature and the
  known gaps.
- Tests: `godot --path . res://tests/test_core.tscn` (182 checks) and
  `res://tests/interaction.tscn` (18 checks). All passed under a software
  Vulkan driver in a cloud container. Nothing has run on real hardware yet.
- Example: `examples/orbit_ship/`. `make_orbit_ship.gd` builds a shuttle
  over Earth with the editor's own code and exports a showcase, a GIF, and a
  transparent sprite sheet. Run it with
  `godot --path . res://examples/orbit_ship/make_orbit_ship.tscn`.
- Example: `examples/lower_orbit_ship/`. The Lower Orbit mining ship (done,
  see below). Run it with
  `godot --path . res://examples/lower_orbit_ship/make_lower_orbit_ship.tscn`.

## Fixed in the second session: the exporter was never committed

The `.gitignore` rule `export/` (meant for Godot build output) also matched
`src/export/`, so `exporter.gd` and `encoders.gd` were never pushed, and
`main.gd`, the tests and the orbit example failed to parse on a fresh clone.
The rule is now `/export/` (project root only), and both files were rebuilt
from how the rest of the code calls them: the same `Exporter.FORMATS` order
(PNG, zipped PNG sequence, GIF, APNG, SVG, direction field),
`default_options()`, `render_frame(host, hub, frame, display_frame, o)`,
`render_sequence()`, `write()`, and `Encoders.gif()` / `apng()` /
`index_image()` / `_crc32()`. The original "GPU OKLab palette-index kernel"
is now a CPU OKLab match with a per-color cache (fast for pixel art).
Checked: all 182 core and 18 interaction tests pass, every format from
`SCENARIO=exports` writes a valid file, and the orbit example re-renders
its showcase within 72 pixels of the committed one (sprite sheet identical).

Headless setup that worked here: Godot 4.3 with `mesa-vulkan-drivers`
(lavapipe), `Xvfb :99`, `DISPLAY=:99` and
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json`. Run
`godot --headless --import --path .` once first so named classes are known.
`test_core` can crash with "corrupted size vs. prev_size" while quitting,
after all checks have printed; the interaction test and examples exit cleanly.

## First things to do on real hardware

1. Run the editor (F5) and both test scenes.
2. Time a 256x256 canvas with 10+ layers. This is the spec's performance
   target and was never measured.
3. Open `examples/orbit_ship/orbit_ship.tessera` to check the project loads.

## Done: a new ship from the Lower Orbit design doc

Built in `examples/lower_orbit_ship/` (see the header of
`make_lower_orbit_ship.gd` for the layers). The palette is the doc's UFO art
(`ufo_reference.png`) through the PNG import, option A: exactly 10 colors,
arranged into ramps. Exports: the mining-scene showcase (PNG + GIF), a
1-pixel-per-cell sprite sheet (rows thrust / tractor beam / shield, 4 frames
each, 66x42 frames), the ship alone (PNG + GIF), and
`lower_orbit_ship_parts.txt` with Chispita hit-box parts. The game sprite is
drawn from the same shape functions as the layers, so the two always match.

Lessons from this pass:
- The LED cell style brightens colors, and Palette Lock then snaps them to a
  different hue (green and gold turned cyan). Use Dot for small colored lights.
- Under ~75% opacity a light color over dark space darkens into a different
  palette entry after Palette Lock; keep palette-critical layers opaque.
- A one-cell outline rule swallows parts that are one or two cells thick
  (barrels, antennas); color those before the outline check.
- Screen blend over a dithered area can snap to an unrelated palette color.

What the design docs said (kept for reference):

The design docs are in the user's Google Drive:
- "Lower Orbit Main Design Doc.drawio"
- "Piloting the Ship.drawio"

What they say about the ship:
- Lower Orbit is a gravity-bound SHMUP with mass-focused upgrades and an
  inventory system ("you owe your soul to the company store"). Zones run
  from On the Planet / Lower Orbit (mining, asteroids) up to The Mother Ship
  and Outer Space. The arc is "from miner to warship". Built on the Chispita
  engine.
- The ship is a company mining ship with:
  - thrusters (main power use; more mass uses more energy)
  - dampers (handling and hover; worse with more mass)
  - a battery (drains as you move, recharges on landing)
  - a cargo bay limited by mass, not slots (bigger ship, bigger bay)
  - a tractor beam (pulls items into the bay)
  - a mining laser (uses battery, also a weapon)
  - bullets (infinite), bombs (bought separately, add mass)
  - a toggleable shield (uses battery)
- Controls: up/down thrust, left/right, Fire, Laser, Special, Item, Tractor
  Beam, Cargo Dump, Shield.
- Art style, from the art embedded in the doc: a pastel palette (pink,
  purple, cyan, green) with dark navy outlines. The logo art is a UFO with a
  green alien pilot and a striped pink/cyan tractor beam animating over 4
  frames. Take the palette from that GIF with the editor's PNG palette
  import (option A, exact colors).

The plan that was agreed (now built):
- A side-view mining ship facing right, with visible parts: thrusters plus
  flame, damper pods, battery lights, cargo bay with ore, tractor-beam
  emitter underneath, mining laser at the nose, a small gun, and a shield
  bubble.
- Build it with a script like `examples/orbit_ship/make_orbit_ship.gd`
  (several tilings, patterns, direction-layer flow for the flame, an
  animated tractor beam, LED battery lights).
- Export a 1-cell-per-pixel sprite sheet for the game. Rows: thrust,
  tractor beam on, shield on. 4 frames each.
- Also export hit-box parts for the shmup. Ships are defined in
  `microstudio/shmup/player_character.txt` with
  `Chispita_addPart(sprite, "rect", w, h)` plus offsets,
  `hit_width`/`hit_height`, `top_speed`, `handling`, then
  `player_ship_measure(ship)` (mass comes from part area, drag from the
  shape).

## Lessons from the orbit-ship pass

- Palette Lock dither fights smooth Display effects (vignette, chromatic
  aberration): it turns them into rings and speckle. Leave dither off when
  those are on.
- Color-aware rounding ignores pattern drives.
- Grout plus corner rounding puts a dot at every tile corner.
