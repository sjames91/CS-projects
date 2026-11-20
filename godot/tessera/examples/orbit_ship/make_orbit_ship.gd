extends Node
## Builds the "Orbit Ship" example with Tessera's own editor code and exports
## it. Run: godot --path . res://examples/orbit_ship/make_orbit_ship.tscn
##
## Layers, bottom to top:
##   Space            square, dithered colour boundaries
##   Stars            square, LED dots
##   Bright stars     square, SVG stamp (sparkle shape from the Shape library)
##   Earth            Voronoi tiling, fractal pattern palette shift
##   Clouds           hex, colour-aware rounding, pattern cutout that drifts
##                    along the "Jet stream" direction layer (animated flow)
##   Atmosphere       hex, screen blend
##   Exhaust          hex, brush-dab flame, follows "Exhaust" direction layer,
##                    4 animated frames, add blend
##   Hull             square, rounded plates + grout seams, Worley weathering
##                    pattern, fine texture
##   Rivets           square with half-both Offset, small dots
##   Glass            hex, colour-aware rounding (smooth canopy)
##   Nav lights       LED dots, blinking per frame
## Display stack: bloom + slight chromatic aberration.

const CS := 6
const W := 112
const H := 64
const SHIP := Vector2(56, 25)  # ship origin in cells
const EARTH_C := Vector2(56, 214)
const EARTH_R := 168.0
const OUT := "res://examples/orbit_ship/"

var app
var main: Control
var noise := FastNoiseLite.new()
var cloud_noise := FastNoiseLite.new()

const PALETTE := [
	"#05060d", "#0d1424", "#1b2a44", "#2e4a6e",                       # 1-4 space
	"#2a2d36", "#454a57", "#6c7383", "#9aa3b3", "#c9d1dc", "#f2f5f8", # 5-10 hull
	"#5a1f12", "#a8401f", "#e0702e", "#ffb357",                       # 11-14 accent
	"#0f3a4a", "#1f7a8c", "#5fd0d8", "#c8fbff",                       # 15-18 glass
	"#7a1d0e", "#e8481c", "#ff9a2e", "#ffe27a", "#fffbe0",            # 19-23 flame
	"#0a2a5e", "#14498f", "#2a77c2", "#63b3e8",                       # 24-27 ocean/atmo
	"#2f6b3a", "#5a9a4a", "#ffffff", "#ff2a3a", "#3aff7a",            # 28-32 land, cloud, nav
]


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 6:
		await get_tree().process_frame
	app = get_node("/root/App")
	noise.seed = 7
	noise.frequency = 0.07
	noise.fractal_octaves = 4
	cloud_noise.seed = 21
	cloud_noise.frequency = 0.09
	cloud_noise.fractal_octaves = 3
	build()
	app.new_project(app.project, "")
	main.canvas.fit_view()
	await settle(40)
	var dir := ProjectSettings.globalize_path(OUT)
	ProjectIO.save(app.project, dir.path_join("orbit_ship.tessera"))
	get_viewport().get_texture().get_image().save_png(dir.path_join("editor.png"))
	await export_all(dir)
	print("ORBIT SHIP DONE")
	get_tree().quit()


func settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ---- geometry (cells, ship-local) ------------------------------------------------

func in_poly(x: float, y: float, pts: Array) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(x, y), PackedVector2Array(pts))


func fus(x: float, y: float) -> bool:
	if x < -24 or x > 26:
		return false
	var h := 6.0
	if x < -18:
		h = 5.0
	elif x > 8:
		h = 6.0 * sqrt(maxf(0.0, 1.0 - pow((x - 8.0) / 18.0, 2)))
	var yc := (x - 8.0) * 0.12 if x > 8 else 0.0
	return y >= yc - h and y <= yc + h * 0.8


func cabin(x: float, y: float) -> bool:
	return pow((x - 12.0) / 9.0, 2) + pow((y + 5.5) / 3.5, 2) <= 1.0


func fin(x: float, y: float) -> bool:
	return in_poly(x, y, [Vector2(-24, -4.5), Vector2(-13, -4.5), Vector2(-19, -15), Vector2(-27, -15)])


func wing(x: float, y: float) -> bool:
	return in_poly(x, y, [Vector2(-15, 2), Vector2(7, 2), Vector2(-5, 10), Vector2(-21, 10)])


func engine(x: float, y: float) -> bool:
	return x >= -30 and x < -23.5 and absf(y) <= 4.2


func nozzle(x: float, y: float) -> bool:
	return x >= -34 and x < -30 and absf(y) <= 2.2 + (-30.0 - x) * 0.55


func antenna(x: float, y: float) -> bool:
	return absf(x + 1.0) < 0.6 and y > -9.5 and y < -5.5


func hull(x: float, y: float) -> bool:
	return fus(x, y) or cabin(x, y) or fin(x, y) or wing(x, y) or engine(x, y) or nozzle(x, y) or antenna(x, y)


func glass(x: float, y: float) -> bool:
	if pow((x - 14.0) / 6.5, 2) + pow((y + 6.0) / 2.4, 2) <= 1.0 and y < -4.4:
		return true
	for px in [-12.0, -7.0, -2.0, 3.0]:
		if Vector2(x, y).distance_to(Vector2(px, -2.3)) < 1.05:
			return true
	return false


func hull_color(x: float, y: float) -> int:
	if not hull(x, y):
		return 0
	if nozzle(x, y):
		return 12 if x < -32.6 else (5 if absf(y) > 1.2 else 6)
	if engine(x, y):
		if absf(y) < 3.2 and int(floor(x)) % 2 == 0:
			return 5
		return 7 if y < -2 else 6
	if antenna(x, y):
		return 9
	var top_edge := not hull(x, y - 1.0)
	var bottom_edge := not hull(x, y + 1.0)
	var side_edge := not hull(x - 1.0, y) or not hull(x + 1.0, y)
	if top_edge:
		return 10
	if bottom_edge or side_edge:
		return 5
	if fin(x, y) and not fus(x, y):
		return 13 if y < -12.5 else (8 if x > -20 else 7)
	if wing(x, y) and not fus(x, y):
		return 12 if y > 8.5 and x < -12 else (7 if y < 6 else 6)
	if fus(x, y) and absf(y - 0.3) < 0.8 and x > -18 and x < 17:
		return 13
	if fus(x, y) and absf(y - 1.3) < 0.5 and x > -18 and x < 15:
		return 12
	if y < -4:
		return 9
	if y < -1:
		return 8
	if y < 2.5:
		return 7
	return 6


# ---- layers ---------------------------------------------------------------------

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


func earth_dist(u: Vector2) -> float:
	return u.distance_to(EARTH_C) - EARTH_R


func build() -> void:
	var p := ProjectData.new()
	p.canvas_cells = Vector2i(W, H)
	p.cell_size = CS
	p.palette = PackedColorArray(PALETTE.map(func(h): return Color.html(h)))
	p.frame_count = 4
	p.frame_durations = PackedInt32Array([90, 90, 90, 90])
	p.fps = 11
	app.project = p
	var px := p.canvas_px()

	# Sparkle stamp shape (stamp shapes come from the Shape Editor library).
	var sparkle := {"id": "sparkle", "name": "Sparkle", "kind": "stamp", "paths": [{"closed": true, "points":
		Array(Svg._poly_path([Vector2(0, -0.5), Vector2(0.07, -0.07), Vector2(0.5, 0), Vector2(0.07, 0.07),
			Vector2(0, 0.5), Vector2(-0.07, 0.07), Vector2(-0.5, 0), Vector2(-0.07, -0.07)], true).points)}]}
	p.shapes["sparkle"] = sparkle
	p.register_shapes()

	var space := layer("Space", "square", {"boundary_mode": 1, "boundary_width": 1.0})
	paint(space, func(u: Vector2, _f: int): return 1 if u.y < 16 else (2 if u.y < 32 else 3))

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var star_cells := {}
	for i in 140:
		star_cells[Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, 52))] = [9, 10, 18, 9][rng.randi() % 4]
	var stars := layer("Stars", "square", {"style": LayerData.Style.LED, "dot_size": 0.45})
	paint(stars, func(u: Vector2, _f: int):
		var c := Vector2i(floor(u.x), floor(u.y))
		return star_cells.get(c, 0) if earth_dist(u) > 2.0 else 0)
	var bright := layer("Bright stars", "square", {"style": LayerData.Style.SVG_STAMP, "stamp_shape": "sparkle", "dot_size": 1.0})
	var bright_cells := [Vector2i(8, 6), Vector2i(31, 3), Vector2i(97, 9), Vector2i(76, 4), Vector2i(104, 30), Vector2i(14, 38), Vector2i(88, 41)]
	paint(bright, func(u: Vector2, _f: int): return 10 if bright_cells.has(Vector2i(floor(u.x), floor(u.y))) else 0)

	var earth := layer("Earth", "voronoi", {"patterns": [_slot({"source": Patterns.Src.FRACTAL, "scale": 3.0,
		"drives": Patterns.Drive.PALETTE_SHIFT, "shift": [-1.0, 1.0], "colors": [25, 26]})]})
	earth.tiling_params = {"jitter": 0.7, "seed": 3}
	paint(earth, func(u: Vector2, _f: int):
		var d := earth_dist(u)
		if d > 0.0:
			return 0
		# Perspective: squash the map toward the limb.
		var n := noise.get_noise_2d(u.x * 0.9, (u.y - 44.0) * 3.0 + 40.0)
		var night := u.x > 92
		if n > 0.22:
			return 28 if night or n < 0.4 else 29
		if d > -1.6:
			return 26
		return 24 if night or n < -0.28 else 25)

	var clouds := layer("Clouds", "hex", {"rounding_on": true, "rounding": 0.8, "rounding_color_aware": true, "rounding_inner": true,
		"flow_patterns": true, "flow_animate": true, "flow_speed": 1.5, "flow_strength": 1.0,
		"patterns": [_slot({"source": Patterns.Src.FRACTAL, "scale": 2.0, "drives": Patterns.Drive.VISIBILITY, "visibility": 0.33})]})
	clouds.opacity = 0.85
	paint(clouds, func(u: Vector2, _f: int):
		if earth_dist(u) > -0.5:
			return 0
		return 30 if cloud_noise.get_noise_2d(u.x * 0.8, (u.y - 44.0) * 3.2) > 0.12 else 0)

	var atmo := layer("Atmosphere", "hex", {"rounding_on": true, "rounding": 0.6})
	atmo.blend_mode = LayerData.Blend.SCREEN
	atmo.opacity = 0.7
	paint(atmo, func(u: Vector2, _f: int):
		var d := earth_dist(u)
		return 27 if d >= -0.6 and d < 1.6 else (4 if d >= 1.6 and d < 3.6 else 0))

	# Engine exhaust: animated frames, follows the Exhaust direction layer.
	var flame := layer("Exhaust", "hex", {"style": LayerData.Style.BRUSH_DAB, "dot_size": 1.0, "flow_stamp_rot": true,
		"jitter_on": true, "jitter_source": 1, "jitter_pos": 0.35, "jitter_size": 0.25, "jitter_rot": 0.2, "flow_strength": 0.9}, false)
	flame.blend_mode = LayerData.Blend.ADD
	var lengths := [15.0, 19.0, 13.0, 17.0]
	paint(flame, func(u: Vector2, f: int):
		var x: float = u.x - SHIP.x
		var y: float = u.y - SHIP.y
		var dd := -34.0 - x
		var L: float = lengths[f]
		if dd < 0.0 or dd > L:
			return 0
		var t := dd / L
		var wob := sin(dd * 0.9 + f * 1.7) * 0.35
		var hh := 2.8 * pow(1.0 - t, 0.6) + wob * (1.0 - t)
		if absf(y) > hh:
			return 0
		var core := absf(y) < hh * 0.45
		if t < 0.15:
			return 23
		if t < 0.35:
			return 22 if core else 21
		if t < 0.62:
			return 21 if core else 20
		if t < 0.85:
			return 20
		return 19)

	var hull_l := layer("Hull", "square", {"rounding_on": true, "rounding": 0.25, "gap_on": true, "gap": 0.07, "grout_color": "#15171c",
		"patterns": [_slot({"source": Patterns.Src.WORLEY, "mode": 0, "scale": 3.0, "drives": Patterns.Drive.PALETTE_SHIFT,
			"shift": [0.0, -1.0], "colors": [7, 8, 9], "fine": true, "fine_amount": 0.18})]})
	paint(hull_l, func(u: Vector2, _f: int): return hull_color(u.x - SHIP.x, u.y - SHIP.y))

	var rivets := layer("Rivets", "square", {"style": LayerData.Style.DOT, "dot_size": 0.22})
	rivets.opacity = 0.75
	paint(rivets, func(u: Vector2, _f: int):
		var x: float = u.x - SHIP.x
		var y: float = u.y - SHIP.y
		var c := Vector2i(floor(u.x), floor(u.y))
		if hull(x, y) and hull(x + 1, y + 1) and not glass(x, y) and (c.x + c.y * 3) % 5 == 0 and not engine(x, y):
			return 5
		return 0)
	app.project.tiling_for(rivets)

	var glass_l := layer("Glass", "hex", {"rounding_on": true, "rounding": 0.9, "rounding_color_aware": true, "rounding_inner": true})
	paint(glass_l, func(u: Vector2, _f: int):
		var x: float = u.x - SHIP.x
		var y: float = u.y - SHIP.y
		if not glass(x, y):
			return 0
		if y < -2.0 and y > -4.0 and x < 6:
			return 17  # portholes
		if y < -7.0:
			return 18
		return 17 if y < -5.4 else 16)

	var nav := layer("Nav lights", "square", {"style": LayerData.Style.LED, "dot_size": 0.95}, false)
	paint(nav, func(u: Vector2, f: int):
		var c := Vector2i(floor(u.x - SHIP.x), floor(u.y - SHIP.y))
		if c == Vector2i(-20, 9) and f < 2:
			return 31
		if c == Vector2i(-26, -15) and (f == 1 or f == 2):
			return 32
		if c == Vector2i(-1, -10) and f == 0:
			return 10
		return 0)

	# Direction layers: exhaust pushes left out of the nozzle; a jet stream
	# curves along the horizon for the drifting clouds.
	var exhaust := layer("Exhaust flow", "square", {}, true, "direction")
	var nz := (SHIP + Vector2(-34, 0)) * CS
	exhaust.strokes_at(0).append(DirStroke.make("arrow", "path", PackedVector2Array([nz, nz - Vector2(24 * CS, 0)]), 10.0 * CS, 1.0))
	exhaust.strokes_at(0).append(DirStroke.make("field", "radial_out", PackedVector2Array([nz - Vector2(6 * CS, 0), nz - Vector2(3 * CS, 0)]), 5.0 * CS, 0.35))
	exhaust.settings["dir"] = {"field_display": 1, "smoothing": 1.5}
	var jet := layer("Jet stream", "square", {}, true, "direction")
	var arc := PackedVector2Array()
	for k in 25:
		var a := deg_to_rad(-90.0 - 22.0 + 44.0 * k / 24.0)
		arc.append((EARTH_C + Vector2(cos(a), sin(a)) * (EARTH_R - 5.0)) * CS)
	jet.strokes_at(0).append(DirStroke.make("curve", "path", arc, 0.0, 1.0))
	jet.settings["dir"] = {"field_display": 2, "smoothing": 4.0}
	flame.settings["flow_layer"] = exhaust.id
	clouds.settings["flow_layer"] = jet.id

	# Draw order: direction layers are not drawn; keep them at the top of the list.
	# No vignette: Palette Lock would snap its gradient into a visible ring.
	p.display = {"bloom_on": true, "bloom_threshold": 0.7, "bloom_radius": 6.0, "bloom_intensity": 0.55,
		"chroma_on": true, "chroma": 0.6}
	p.palette_lock = {"enabled": true, "dither": true, "strength": 0.3}
	for l in p.layers:
		LayerData.normalize_settings(l.settings)


func _slot(over: Dictionary) -> Dictionary:
	var s := Patterns.default_slot()
	s.merge(over, true)
	return s


# ---- exports --------------------------------------------------------------------

func export_all(dir: String) -> void:
	var hub: RenderHub = main.hub
	var o := Exporter.default_options()
	o.scale = 2
	print(await Exporter.write(main, hub, dir.path_join("orbit_ship_showcase.png"), o))
	o.format = 2  # GIF
	o.repeat = 2
	print(await Exporter.write(main, hub, dir.path_join("orbit_ship_showcase.gif"), o))
	# Game sprite: ship + exhaust only, transparent, no Display stack, cropped.
	var keep := ["Exhaust", "Hull", "Rivets", "Glass", "Nav lights"]
	var saved_display: Dictionary = app.project.display
	app.project.display = {}
	app.project.palette_lock = {"enabled": true, "dither": false, "strength": 0.0}
	for l in app.project.layers:
		if not l.is_direction():
			l.visible = keep.has(l.name)
	await settle(4)
	var crop := Rect2i(Vector2i((SHIP + Vector2(-56, -17)) * CS * 2), Vector2i(Vector2(85, 30) * CS * 2))
	var sheet := Image.create(crop.size.x * 4, crop.size.y, false, Image.FORMAT_RGBA8)
	var frames: Array = []
	for f in 4:
		var o2 := Exporter.default_options()
		o2.scale = 2
		var img: Image = await Exporter.render_frame(main, hub, f, f, o2)
		var cut := img.get_region(crop)
		frames.append(cut)
		sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, crop.size), Vector2i(crop.size.x * f, 0))
	sheet.save_png(dir.path_join("orbit_ship_sprite_sheet.png"))
	(frames[0] as Image).save_png(dir.path_join("orbit_ship_sprite.png"))
	var f3 := FileAccess.open(dir.path_join("orbit_ship_sprite.gif"), FileAccess.WRITE)
	f3.store_buffer(Encoders.gif(frames, [9, 9, 9, 9], app.project.palette))
	f3 = null
	app.project.display = saved_display
	for l in app.project.layers:
		l.visible = true
