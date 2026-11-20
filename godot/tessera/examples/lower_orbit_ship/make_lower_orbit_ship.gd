extends Node
## Builds the Lower Orbit mining ship with Tessera's own editor code and
## exports it. Run: godot --path . res://examples/lower_orbit_ship/make_lower_orbit_ship.tscn
##
## The ship comes from the Lower Orbit design docs ("Lower Orbit Main Design
## Doc" and "Piloting the Ship"): a company mining ship with thrusters,
## hover dampers, a battery, a cargo bay limited by mass, a tractor beam
## underneath, a mining laser at the nose, a gun, and a shield. The palette
## is imported from the UFO art in the design doc (ufo_reference.png) with
## the editor's PNG palette import, option A (exact colors).
##
## Showcase layers, bottom to top:
##   Space            square, navy with a dithered glow toward the planet
##   Stars            square, LED dots
##   Planet           Voronoi, fractal palette shift (pastel bands)
##   Atmosphere       hex, a cyan rim
##   Asteroids        hex, colour-aware rounding, Worley weathering
##   Ore              square, dots in the rock
##   Tractor beam     square, pink/cyan stripes that animate like the logo
##   Ore chunks       hex, colour-aware rounding, rising through the beam
##   Exhaust          hex, brush dabs following the "Exhaust flow" layer
##   Hull             square, plates with grout seams
##   Glass            hex, colour-aware rounding (smooth canopy)
##   Pilot            square (the green alien from the logo)
##   Lights           dots: battery bar, damper glow, antenna tip
##   Laser            square, add blend, flickering beam into the asteroid
##   Sparks           hex, brush dabs where the laser cuts
##   Shield           hex, screen blend (hidden in the showcase)
## Display stack: soft bloom. Palette Lock on (no dither).
##
## Exports (into this folder):
##   lower_orbit_ship_showcase.png / .gif   the mining scene
##   lower_orbit_ship_sheet.png             game sprite sheet, 1 pixel per cell:
##                                          rows thrust, tractor beam, shield;
##                                          4 frames each
##   lower_orbit_ship.png / .gif            the ship alone (thrust row)
##   lower_orbit_ship_parts.txt             Chispita hit-box parts for the shmup
##   lower_orbit_ship.tessera, editor.png   the project and an editor screenshot

const CS := 6
const W := 112
const H := 64
const SHIP := Vector2(44, 22)  # ship origin in cells (x right, y down)
const PLANET_C := Vector2(56, 262)
const PLANET_R := 208.0
const ROCK_C := Vector2(96, 23)  # the asteroid being mined
const OUT := "res://examples/lower_orbit_ship/"

## Palette, in ramp order. The colors are the UFO art's own, imported below.
const RAMP := ["#0a0726", "#442d7d", "#8245a9", "#cd407f", "#e89cc3", "#f0c5f1",
	"#6acce8", "#2f833f", "#3ba353", "#c8993e"]
const NAVY := 1
const DPURPLE := 2
const PURPLE := 3
const MAGENTA := 4
const PINK := 5
const LPINK := 6
const CYAN := 7
const DGREEN := 8
const GREEN := 9
const GOLD := 10

## Sprite sheet frame, in ship cells: covers the ship, the flame, the shield
## and the top of the tractor beam.
const FRAME := Rect2i(-38, -17, 66, 42)

var app
var main: Control
var noise := FastNoiseLite.new()


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 6:
		await get_tree().process_frame
	app = get_node("/root/App")
	noise.seed = 11
	noise.frequency = 0.12
	noise.fractal_octaves = 3
	build()
	app.new_project(app.project, "")
	main.canvas.fit_view()
	await settle(40)
	var dir := ProjectSettings.globalize_path(OUT)
	ProjectIO.save(app.project, dir.path_join("lower_orbit_ship.tessera"))
	get_viewport().get_texture().get_image().save_png(dir.path_join("editor.png"))
	await export_all(dir)
	print("LOWER ORBIT SHIP DONE")
	get_tree().quit()


func settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ---- palette ----------------------------------------------------------------------

## The editor's PNG palette import, option A: every exact color in the image.
func import_palette() -> PackedColorArray:
	var img := Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("ufo_reference.png")))
	var found: PackedColorArray = Gpu.unique_colors(img, 255).colors
	var out := PackedColorArray()
	for h in RAMP:
		var want := Color.html(h)
		var best := found[0]
		for c in found:
			if OkLab.distance(c, want) < OkLab.distance(best, want):
				best = c
		out.append(best)
	assert(found.size() == RAMP.size(), "the UFO art should have %d colors, found %d" % [RAMP.size(), found.size()])
	return out


# ---- ship shape (ship cells: x right, y down, origin mid-hull) ------------------------

func in_poly(x: float, y: float, pts: Array) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(x, y), PackedVector2Array(pts))


func body(x: float, y: float) -> bool:
	return in_poly(x, y, [Vector2(-16, -4.5), Vector2(-13.5, -5.5), Vector2(9, -5.5), Vector2(15, -2.5),
		Vector2(18.6, -0.4), Vector2(18.6, 2.8), Vector2(15, 5.5), Vector2(-13.5, 5.5), Vector2(-16, 4.5)])


func dome(x: float, y: float) -> bool:
	return pow((x - 5.0) / 6.6, 2) + pow((y + 5.5) / 4.6, 2) <= 1.0 and y < -3.5


func cargo(x: float, y: float) -> bool:
	return in_poly(x, y, [Vector2(-12, 4), Vector2(6, 4), Vector2(4.5, 9.4), Vector2(-10.5, 9.4)])


func emitter(x: float, y: float) -> bool:
	return in_poly(x, y, [Vector2(-6.2, 9), Vector2(0.2, 9), Vector2(-0.8, 11.2), Vector2(-5.2, 11.2)])


func pod(x: float, y: float) -> bool:
	for c in [Vector2(-14.5, 6.6), Vector2(10.5, 6.2)]:
		if pow((x - c.x) / 3.1, 2) + pow((y - c.y) / 1.7, 2) <= 1.0:
			return true
	return false


func housing(x: float, y: float) -> bool:
	return x >= -21 and x < -15.5 and absf(y) <= 3.6


func nozzle(x: float, y: float) -> bool:
	return x >= -24.5 and x < -21 and absf(y) <= 2.0 + (-21.0 - x) * 0.55


func laser_barrel(x: float, y: float) -> bool:
	return x >= 18 and x < 22.5 and y >= 0.0 and y < 2.0


func gun(x: float, y: float) -> bool:
	return x >= 12 and x < 17.5 and y >= 4.4 and y < 5.6


func antenna(x: float, y: float) -> bool:
	return floor(x) == -7.0 and y > -10.5 and y < -5


func hull(x: float, y: float) -> bool:
	return body(x, y) or dome(x, y) or cargo(x, y) or emitter(x, y) or pod(x, y) or housing(x, y) \
		or nozzle(x, y) or laser_barrel(x, y) or gun(x, y) or antenna(x, y)


func glass(x: float, y: float) -> bool:
	return pow((x - 5.0) / 5.3, 2) + pow((y + 5.6) / 3.4, 2) <= 1.0 and y < -3.9


## The cargo window: ore inside the bay shows through it.
func cargo_window(x: float, y: float) -> bool:
	return x >= -9.5 and x < 2.5 and y >= 5.6 and y < 8.0


func hull_color(x: float, y: float) -> int:
	if not hull(x, y):
		return 0
	# Thin parts first: an outline would swallow them whole.
	if antenna(x, y) and not body(x, y):
		return MAGENTA if y < -9.5 else PINK
	if laser_barrel(x, y) and not body(x, y):
		return MAGENTA if x >= 21.5 else (LPINK if y < 1.0 else PURPLE)
	if gun(x, y) and not body(x, y):
		return CYAN if x >= 16.5 else PURPLE
	# One-cell navy outline all round, like the logo art.
	if not hull(x, y - 1.0) or not hull(x, y + 1.0) or not hull(x - 1.0, y) or not hull(x + 1.0, y):
		return NAVY
	if nozzle(x, y):
		return MAGENTA if x < -23.5 else (DPURPLE if absf(y) > 1.2 else PURPLE)
	if housing(x, y):
		if absf(y) < 2.6 and int(floor(x)) % 2 == 0:
			return DPURPLE
		return PINK if y < -1.5 else PURPLE
	if pod(x, y) and not body(x, y) and not cargo(x, y):
		return CYAN if y > 7.2 else PURPLE
	if emitter(x, y) and not cargo(x, y):
		return CYAN if y > 10.0 else DPURPLE
	if cargo(x, y) and not body(x, y):
		if cargo_window(x, y):
			# Ore piled in the bay: green and gold chunks on dark purple.
			var n := noise.get_noise_2d(x * 2.0, y * 2.0)
			if y > 6.6 and n > 0.1:
				return GOLD if n > 0.35 else GREEN
			return DGREEN if y > 7.2 and n > -0.15 else DPURPLE
		return DPURPLE if y > 8.2 else PURPLE
	if dome(x, y) and not body(x, y):
		return LPINK
	# Body: a magenta band under the canopy (like the logo's rim), a pink
	# company stripe, light top, purple middle, dark purple belly.
	if y < -4.4 and x > -1 and x < 11:
		return MAGENTA
	if y > 0.6 and y < 1.8 and x > -14 and x < 15:
		return PINK
	if y < -3.8:
		return LPINK
	if y < 2.6:
		return PURPLE
	return DPURPLE


func glass_color(x: float, y: float) -> int:
	if not glass(x, y):
		return 0
	if y < -8.0 and x < 6:
		return LPINK  # glare
	return LPINK if y < -6.8 else PINK


## The pilot: a little green alien from the logo, behind the canopy glass.
func pilot_color(x: float, y: float) -> int:
	var c := Vector2i(floor(x), floor(y))
	var head := {Vector2i(5, -7): GREEN, Vector2i(6, -7): GREEN, Vector2i(4, -6): GREEN, Vector2i(5, -6): NAVY,
		Vector2i(6, -6): GREEN, Vector2i(7, -6): NAVY, Vector2i(4, -5): DGREEN, Vector2i(5, -5): GREEN,
		Vector2i(6, -5): GREEN, Vector2i(7, -5): DGREEN, Vector2i(5, -8): MAGENTA}
	return head.get(c, 0)


## Lights: battery bar (charging animation), damper glow, antenna tip blink.
func light_color(x: float, y: float, f: int) -> int:
	var c := Vector2i(floor(x), floor(y))
	if c.y == -2 and c.x >= -12 and c.x <= -2 and posmod(c.x, 2) == 0:
		var k := (c.x + 12) / 2  # 0..5 along the bar
		if k > 2 + (f % 4):
			return DPURPLE  # not yet charged
		return GREEN if k < 3 else (GOLD if k < 5 else MAGENTA)
	if c == Vector2i(-7, -11) and f % 2 == 0:
		return MAGENTA
	if c.y == 8 and (c.x == -15 or c.x == -14 or c.x == 10 or c.x == 11) and (f + c.x) % 2 == 0:
		return CYAN
	return 0


## Exhaust flame, pastel: light pink core to magenta to dark purple tips.
func flame_color(x: float, y: float, f: int) -> int:
	var lengths := [11.0, 14.0, 10.0, 13.0]
	var dd := -24.5 - x
	var L: float = lengths[f % 4]
	if dd < 0.0 or dd > L:
		return 0
	var t := dd / L
	var wob := sin(dd * 0.9 + f * 1.7) * 0.35
	var hh := 2.4 * pow(1.0 - t, 0.6) + wob * (1.0 - t)
	if absf(y) > hh:
		return 0
	var core := absf(y) < hh * 0.45
	if t < 0.2:
		return LPINK
	if t < 0.45:
		return LPINK if core else PINK
	if t < 0.7:
		return PINK if core else MAGENTA
	if t < 0.9:
		return MAGENTA
	return DPURPLE


## Tractor beam: a cone under the emitter with pink and cyan stripes that
## travel up the beam (the logo GIF's animation). `reach` = beam length.
func beam_color(x: float, y: float, f: int, reach: float) -> int:
	var dy := y - 11.2
	if dy < 0.0 or dy > reach:
		return 0
	var half := 2.2 + dy * 0.42
	if absf(x + 3.0) > half:
		return 0
	var band := int(floor((dy + f * 0.75) / 1.5))
	return PINK if band % 2 == 0 else CYAN


## Shield: a shimmering cyan ring around the ship.
func shield_color(x: float, y: float, f: int) -> int:
	var e := Vector2((x + 3.0) / 27.0, (y + 0.5) / 15.5)
	var r := e.length()
	if r < 0.93 or r > 1.0:
		return 0
	var a := atan2(e.y, e.x)
	return CYAN if sin(a * 9.0 + f * 1.57) > -0.6 else 0


# ---- the scene around the ship ---------------------------------------------------------

func planet_dist(u: Vector2) -> float:
	return u.distance_to(PLANET_C) - PLANET_R


func rock_r(center: Vector2, r: float, u: Vector2, seed_: float) -> float:
	var d := u - center
	var a := atan2(d.y, d.x)
	return r * (1.0 + 0.16 * sin(a * 3.0 + seed_) + 0.09 * sin(a * 5.0 + seed_ * 2.0))


const ROCKS := [[Vector2(96, 23), 9.0, 0.0], [Vector2(18, 9), 4.0, 1.3], [Vector2(74, 7), 2.6, 2.1],
	[Vector2(106, 47), 4.5, 3.7], [Vector2(9, 42), 3.0, 0.7], [Vector2(62, 41), 2.0, 5.2]]


## Which rock (index) a cell belongs to, or -1.
func rock_at(u: Vector2) -> int:
	for i in ROCKS.size():
		var rk: Array = ROCKS[i]
		var d: float = u.distance_to(rk[0])
		if d <= rock_r(rk[0], rk[1], u, rk[2]):
			# The laser has cut a notch out of the big one.
			if i == 0 and u.x < 89.5 and absf(u.y - (SHIP.y + 1.0)) < 1.6:
				return -1
			return i
	return -1


func rock_color(u: Vector2) -> int:
	var i := rock_at(u)
	if i < 0:
		return 0
	var rk: Array = ROCKS[i]
	var d := u - (rk[0] as Vector2)
	if rock_at(u + Vector2(0, -1)) < 0 or rock_at(u + Vector2(0, 1)) < 0 or rock_at(u + Vector2(-1, 0)) < 0 or rock_at(u + Vector2(1, 0)) < 0:
		return NAVY
	# Lit from the top left.
	var lit := (-d.x - d.y) / (rk[1] as float)
	if lit > 0.55:
		return PURPLE
	return DPURPLE


func ore_color(u: Vector2) -> int:
	var i := rock_at(u)
	if i < 0 or rock_color(u) == NAVY:
		return 0
	var n := noise.get_noise_2d(u.x * 1.7 + i * 30.0, u.y * 1.7)
	if n > 0.42:
		return GOLD
	if n < -0.45:
		return GREEN
	return 0


## Ore chunks rising through the tractor beam (ship cells, per frame).
func chunk_color(x: float, y: float, f: int) -> int:
	var chunks := [[Vector2(-4.0, 16.0), GREEN], [Vector2(-1.5, 21.5), GOLD], [Vector2(-5.5, 26.0), GREEN], [Vector2(-2.0, 13.0), GOLD]]
	for ch in chunks:
		var c: Vector2 = ch[0] - Vector2(0, f * 0.9)
		var r := 1.25 if ch[1] == GOLD else 1.55
		var d := Vector2(x, y).distance_to(c)
		if d <= r:
			return DGREEN if (ch[1] == GREEN and x - c.x > 0.4) else ch[1]
	return 0


func laser_color(x: float, y: float, f: int) -> int:
	var end := ROCK_C.x - SHIP.x - 6.2
	if x < 22.5 or x > end:
		return 0
	var row := int(floor(y))
	if row == 0 or row == 1:
		return LPINK
	if row == -1 or row == 2:
		return MAGENTA if (f + int(floor(x / 3.0))) % 4 != 0 else 0
	return 0


func spark_color(x: float, y: float, f: int) -> int:
	var end := ROCK_C.x - SHIP.x - 6.2
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + f
	for k in 9:
		var p := Vector2(end - rng.randf_range(0.0, 4.5), 1.0 + rng.randf_range(-4.0, 4.0))
		if Vector2(x, y).distance_to(p) < 0.7:
			return GOLD if k % 3 else LPINK
	return 0


# ---- layers -------------------------------------------------------------------------

func layer(name_: String, tiling: String, settings: Dictionary, is_static := true, kind := "pixel") -> LayerData:
	var p: ProjectData = app.project
	var l := p.add_layer(name_, kind)
	l.tiling_id = tiling
	l.tiling_params = TilingRegistry.default_params(tiling)
	for k in settings:
		l.settings[k] = settings[k]
	if is_static and kind == "pixel":
		l.is_static = true
		l.frames = [l.frames[0]] as Array[PackedByteArray]
	app.project.tiling_for(l)
	return l


## Paint every cell of every frame of a layer from a function of the cell
## center (cells) and frame.
func paint(l: LayerData, fn: Callable) -> void:
	var t: Tiling = app.tiling_of(l)
	for fi in l.frames.size():
		var d := l.frames[fi]
		for i in d.size():
			var c := t.cell_of_index(i)
			d[i] = fn.call(t.cell_center(c) / CS, fi)


## Same, with ship-local coordinates.
func paint_ship(l: LayerData, fn: Callable) -> void:
	paint(l, func(u: Vector2, f: int): return fn.call(u.x - SHIP.x, u.y - SHIP.y, f))


func _slot(over: Dictionary) -> Dictionary:
	var s := Patterns.default_slot()
	s.merge(over, true)
	return s


## 4x4 ordered-dither threshold in [0,1).
func bayer(c: Vector2i) -> float:
	var m := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	return (m[(c.y & 3) * 4 + (c.x & 3)] + 0.5) / 16.0


func build() -> void:
	var p := ProjectData.new()
	p.canvas_cells = Vector2i(W, H)
	p.cell_size = CS
	p.frame_count = 4
	p.frame_durations = PackedInt32Array([110, 110, 110, 110])
	p.fps = 9
	app.project = p
	p.palette = import_palette()

	# Space: navy, with a dithered dark purple glow toward the planet.
	var space := layer("Space", "square", {})
	paint(space, func(u: Vector2, _f: int):
		var d := planet_dist(u)
		var t := clampf(1.0 - (d - 1.5) / 4.0, 0.0, 1.0)
		var c := Vector2i(floor(u.x), floor(u.y))
		return DPURPLE if d < 1.5 or bayer(c) < t * 0.7 else NAVY)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var star_cells := {}
	for i in 90:
		star_cells[Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, 46))] = [LPINK, CYAN, PINK, LPINK][rng.randi() % 4]
	var stars := layer("Stars", "square", {"style": LayerData.Style.LED, "dot_size": 0.5})
	paint(stars, func(u: Vector2, _f: int):
		var c := Vector2i(floor(u.x), floor(u.y))
		return star_cells.get(c, 0) if planet_dist(u) > 3.0 and rock_at(u) < 0 else 0)

	var planet := layer("Planet", "voronoi", {"patterns": [_slot({"source": Patterns.Src.FRACTAL, "scale": 3.0,
		"drives": Patterns.Drive.PALETTE_SHIFT, "shift": [-1.0, 1.0], "colors": [PINK, PURPLE]})]})
	planet.tiling_params = {"jitter": 0.75, "seed": 9}
	paint(planet, func(u: Vector2, _f: int):
		var d := planet_dist(u)
		if d > 0.0:
			return 0
		var n := noise.get_noise_2d(u.x * 0.5, d * 2.6 + 30.0)
		if d > -1.4:
			return LPINK
		if n > 0.25:
			return PINK
		return PURPLE if n > -0.2 else DPURPLE)

	var atmo := layer("Atmosphere", "hex", {"rounding_on": true, "rounding": 1.0, "rounding_color_aware": true, "rounding_inner": true})
	paint(atmo, func(u: Vector2, _f: int):
		var d := planet_dist(u)
		return CYAN if d >= -0.4 and d < 0.9 else 0)

	var rocks := layer("Asteroids", "hex", {"rounding_on": true, "rounding": 0.7, "rounding_color_aware": true, "rounding_inner": true})
	paint(rocks, func(u: Vector2, _f: int): return rock_color(u))

	var ore := layer("Ore", "square", {"style": LayerData.Style.DOT, "dot_size": 0.75})
	paint(ore, func(u: Vector2, _f: int): return ore_color(u))

	var beam := layer("Tractor beam", "square", {}, false)
	paint_ship(beam, func(x: float, y: float, f: int): return beam_color(x, y, f, 17.5))

	var chunks := layer("Ore chunks", "hex", {"rounding_on": true, "rounding": 0.9, "rounding_color_aware": true, "rounding_inner": true}, false)
	paint_ship(chunks, func(x: float, y: float, f: int): return chunk_color(x, y, f))


	var flame := layer("Exhaust", "hex", {"style": LayerData.Style.BRUSH_DAB, "dot_size": 1.0, "flow_stamp_rot": true,
		"jitter_on": true, "jitter_source": 1, "jitter_pos": 0.35, "jitter_size": 0.25, "jitter_rot": 0.2, "flow_strength": 0.9}, false)
	flame.blend_mode = LayerData.Blend.ADD
	paint_ship(flame, func(x: float, y: float, f: int): return flame_color(x, y, f))

	var hull_l := layer("Hull", "square", {"gap_on": true, "gap": 0.04, "grout_color": "#2b1d52"})
	paint_ship(hull_l, func(x: float, y: float, _f: int): return hull_color(x, y))

	var glass_l := layer("Glass", "hex", {"rounding_on": true, "rounding": 0.9, "rounding_color_aware": true, "rounding_inner": true})
	glass_l.opacity = 0.9
	paint_ship(glass_l, func(x: float, y: float, _f: int): return glass_color(x, y))

	var pilot := layer("Pilot", "square", {})
	paint_ship(pilot, func(x: float, y: float, _f: int): return pilot_color(x, y))

	var lights := layer("Lights", "square", {"style": LayerData.Style.DOT, "dot_size": 0.85}, false)
	paint_ship(lights, func(x: float, y: float, f: int): return light_color(x, y, f))

	var laser := layer("Laser", "square", {}, false)
	laser.blend_mode = LayerData.Blend.ADD
	paint_ship(laser, func(x: float, y: float, f: int): return laser_color(x, y, f))

	var sparks := layer("Sparks", "hex", {"style": LayerData.Style.BRUSH_DAB, "dot_size": 0.8,
		"jitter_on": true, "jitter_pos": 0.3, "jitter_rot": 0.5}, false)
	sparks.blend_mode = LayerData.Blend.ADD
	paint_ship(sparks, func(x: float, y: float, f: int): return spark_color(x, y, f))

	var shield := layer("Shield", "hex", {"rounding_on": true, "rounding": 0.6, "rounding_color_aware": true}, false)
	shield.blend_mode = LayerData.Blend.SCREEN
	shield.opacity = 0.7
	shield.visible = false  # shown in the sprite sheet's shield row
	paint_ship(shield, func(x: float, y: float, f: int): return shield_color(x, y, f))

	# The exhaust pushes left out of the nozzle.
	var exhaust := layer("Exhaust flow", "square", {}, true, "direction")
	var nz := (SHIP + Vector2(-24.5, 0)) * CS
	exhaust.strokes_at(0).append(DirStroke.make("arrow", "path", PackedVector2Array([nz, nz - Vector2(18 * CS, 0)]), 8.0 * CS, 1.0))
	exhaust.strokes_at(0).append(DirStroke.make("field", "radial_out", PackedVector2Array([nz - Vector2(5 * CS, 0), nz - Vector2(2 * CS, 0)]), 4.0 * CS, 0.35))
	exhaust.settings["dir"] = {"field_display": 1, "smoothing": 1.5}
	flame.settings["flow_layer"] = exhaust.id

	# Soft bloom on the brightest things only; no vignette or dither (they
	# fight Palette Lock, see the orbit ship notes).
	p.display = {"bloom_on": true, "bloom_threshold": 0.85, "bloom_radius": 6.0, "bloom_intensity": 0.45}
	p.palette_lock = {"enabled": true, "dither": false, "strength": 0.0}
	for l in p.layers:
		LayerData.normalize_settings(l.settings)


# ---- game sprite (1 pixel per cell) ---------------------------------------------------

## The ship as game pixel art, one pixel per cell, from the same shape
## functions the layers use. row 0 thrust, 1 tractor beam on, 2 shield on.
func sprite_frame(f: int, row: int) -> Image:
	var pal: PackedColorArray = app.project.palette
	var img := Image.create(FRAME.size.x, FRAME.size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for py in FRAME.size.y:
		for px in FRAME.size.x:
			var x := FRAME.position.x + px + 0.5
			var y := FRAME.position.y + py + 0.5
			var c := 0
			for fn in [
				func(): return shield_color(x, y, f) if row == 2 else 0,
				func(): return pilot_color(x, y),
				func(): return light_color(x, y, f),
				func(): return glass_color(x, y),
				func(): return hull_color(x, y),
				func(): return flame_color(x, y, f),
				func(): return chunk_color(x, y, f) if row == 1 else 0,
				func(): return beam_color(x, y, f, 13.0) if row == 1 else 0,
			]:
				c = fn.call()
				if c != 0:
					break
			if c != 0:
				img.set_pixel(px, py, pal[c - 1])
	return img


## Hit-box parts for Chispita (microScript), matching the sprite's frame:
## the sprite is drawn centered on the frame, y points up.
func chispita_parts() -> String:
	var center := Vector2(FRAME.position) + Vector2(FRAME.size) / 2.0
	var parts := [
		["main hull", Rect2(-16, -5.5, 34.6, 11)],
		["cargo bay", Rect2(-12, 4, 18, 5.4)],
		["canopy", Rect2(-1.6, -10, 13.2, 4.5)],
		["thruster", Rect2(-24.5, -3.6, 9, 7.2)],
	]
	var lines := PackedStringArray([
		"// Lower Orbit mining ship: hit-box parts for lower_orbit_ship_sheet.png",
		"// (frames %d x %d pixels; the sprite is drawn centered on its frame)." % [FRAME.size.x, FRAME.size.y],
		"// Generated by examples/lower_orbit_ship/make_lower_orbit_ship.gd in Tessera.",
		"",
		"lower_orbit_ship_parts = function(ship)",
	])
	var main_r: Rect2 = parts[0][1]
	var mc := main_r.get_center() - center
	lines.append("  ship.hit_width = %s" % snappedf(main_r.size.x, 0.1))
	lines.append("  ship.hit_height = %s" % snappedf(main_r.size.y, 0.1))
	lines.append("  ship.hit_offset_x = %s" % snappedf(mc.x, 0.1))
	lines.append("  ship.hit_offset_y = %s" % snappedf(-mc.y, 0.1))
	for i in range(1, parts.size()):
		var r: Rect2 = parts[i][1]
		var o := r.get_center() - center
		lines.append("  local %s = Chispita_addPart(ship, \"rect\", %s, %s)  // %s" % [
			parts[i][0].replace(" ", "_"), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1), parts[i][0]])
		lines.append("  %s.offset_x = %s" % [parts[i][0].replace(" ", "_"), snappedf(o.x, 0.1)])
		lines.append("  %s.offset_y = %s" % [parts[i][0].replace(" ", "_"), snappedf(-o.y, 0.1)])
	lines.append("end")
	return "\n".join(lines) + "\n"


# ---- exports --------------------------------------------------------------------------

func export_all(dir: String) -> void:
	var hub: RenderHub = main.hub
	var o := Exporter.default_options()
	o.scale = 2
	print(await Exporter.write(main, hub, dir.path_join("lower_orbit_ship_showcase.png"), o))
	o.format = 2  # GIF
	o.repeat = 2
	print(await Exporter.write(main, hub, dir.path_join("lower_orbit_ship_showcase.gif"), o))

	# Game sprite sheet: rows thrust / tractor beam / shield, 4 frames each.
	var sheet := Image.create(FRAME.size.x * 4, FRAME.size.y * 3, false, Image.FORMAT_RGBA8)
	var thrust: Array = []
	for row in 3:
		for f in 4:
			var img := sprite_frame(f, row)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, FRAME.size), Vector2i(FRAME.size.x * f, FRAME.size.y * row))
			if row == 0:
				thrust.append(img)
	sheet.save_png(dir.path_join("lower_orbit_ship_sheet.png"))
	(thrust[0] as Image).save_png(dir.path_join("lower_orbit_ship.png"))
	var gf := FileAccess.open(dir.path_join("lower_orbit_ship.gif"), FileAccess.WRITE)
	gf.store_buffer(Encoders.gif(thrust, [11, 11, 11, 11], app.project.palette))
	gf = null
	var pf := FileAccess.open(dir.path_join("lower_orbit_ship_parts.txt"), FileAccess.WRITE)
	pf.store_string(chispita_parts())
	pf = null
	print("Exported lower_orbit_ship_sheet.png, lower_orbit_ship.png/.gif, lower_orbit_ship_parts.txt")
