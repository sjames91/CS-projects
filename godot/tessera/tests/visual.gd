extends Node
## Visual scenarios for eyeballing features: SCENARIO=<name> SHOT_DIR=<dir>.
## Each scenario builds layers through App/tool code and saves <name>.png.

var app
var main: Control
var cv: CanvasView


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 6:
		await get_tree().process_frame
	app = get_node("/root/App")
	cv = main.canvas
	var name_ := OS.get_environment("SCENARIO")
	await call(name_)
	cv.fit_view()
	if OS.get_environment("ZOOM") != "":
		cv.zoom = float(OS.get_environment("ZOOM"))
		var at := OS.get_environment("AT").split(",")
		cv.center_on(Vector2(float(at[0]), float(at[1])))
	for i in 24:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(name_ + OS.get_environment("SUFFIX") + ".png"))
	get_tree().quit()


func fill_layer(l: LayerData, fn: Callable) -> void:
	var t: Tiling = app.tiling_of(l)
	var d := l.cells(0)
	for i in d.size():
		d[i] = fn.call(t.cell_of_index(i), t.cell_center(t.cell_of_index(i)))
	app.layer_cells_changed.emit(l.id)


func new_layer(name_: String, setup: Callable) -> LayerData:
	var out: Array = []
	app.perform("add", func():
		var l: LayerData = app.project.add_layer(name_)
		setup.call(l)
		app.active_layer_id = l.id
		out.append(l))
	return out[0]


func offset() -> void:
	var bg: LayerData = app.active_layer()
	fill_layer(bg, func(c, p): return 2 if (c.x + c.y) % 2 == 0 else 3)
	var a := new_layer("half both dots", func(l):
		l.settings.style = LayerData.Style.DOT
		l.settings.dot_size = 0.5)
	app.set_layer_offset(a, OffsetTiling.Mode.HALF_BOTH)
	fill_layer(a, func(c, p): return 9 if p.x < 300 else 0)
	var b := new_layer("brick", func(l):
		l.settings.gap_on = true
		l.settings.gap = 0.15)
	app.set_layer_offset(b, OffsetTiling.Mode.BRICK_ROWS)
	fill_layer(b, func(c, p): return (16 + (c.y % 3)) if p.x > 260 and p.y > 260 else 0)
	app.set_tool("pencil")
	var tc := ToolController.new()
	tc.press(Vector2(270, 270), false, {})
	tc.release(Vector2(270, 270), {})


func display() -> void:
	var bg: LayerData = app.active_layer()
	fill_layer(bg, func(c, p): return [16, 17, 18, 19, 6, 9, 10][int(p.x / 74) % 7] if p.y < 380 else (2 if (c.x / 4 + c.y / 4) % 2 == 0 else 6))
	app.perform("p", func():
		var d := DisplayStack.DEFAULTS.duplicate()
		d.merge(DisplayStack.PRESETS["Consumer TV"].display, true)
		app.project.display = d
		for k in DisplayStack.PRESETS["Consumer TV"].crt:
			bg.settings[k] = DisplayStack.PRESETS["Consumer TV"].crt[k])
	app.set_view("preview_lock", false)


func patterns() -> void:
	var bg: LayerData = app.active_layer()
	fill_layer(bg, func(c, p): return 17 if p.y < 256 else (9 if p.x < 256 else 13))
	var sl := Patterns.default_slot()
	sl.source = Patterns.Src.FRACTAL
	sl.drives = Patterns.Drive.STYLE | Patterns.Drive.SIZE
	sl.styles = [0, 1, 0]
	sl.style_count = 2
	sl.size = [0.4, 1.1]
	sl.scale = 6.0
	var rd := Patterns.default_slot()
	rd.source = Patterns.Src.REACTION_DIFFUSION
	rd.iterations = 1500
	rd.scale = 2.0
	rd.drives = Patterns.Drive.VISIBILITY
	rd.visibility = 0.25
	rd.colors = [9]
	var hat := Patterns.default_slot()
	hat.source = Patterns.Src.WORLEY
	hat.mode = 1
	hat.drives = Patterns.Drive.PALETTE_SHIFT
	hat.shift = [-2.0, 1.0]
	hat.colors = [13]
	hat.fine = true
	hat.fine_amount = 0.6
	app.perform("pat", func(): bg.settings.patterns = [sl, rd, hat])


func patterns_map() -> void:
	await patterns()
	app.pattern_view[app.active_layer_id] = 1
	app.view_changed.emit()


func turing() -> void:
	var bg: LayerData = app.active_layer()
	fill_layer(bg, func(c, p): return 19)
	var rd := Patterns.default_slot()
	rd.source = Patterns.Src.REACTION_DIFFUSION
	rd.feed = 0.0545
	rd.kill = 0.062
	rd.iterations = 3000
	rd.scale = 1.0
	rd.drives = Patterns.Drive.STYLE | Patterns.Drive.PALETTE_SHIFT
	rd.styles = [1, 0, 0]
	rd.shift = [-3.0, 0.0]
	app.perform("pat", func(): bg.settings.patterns = [rd])


func direction() -> void:
	var bg: LayerData = app.active_layer()
	fill_layer(bg, func(c, p): return 5)
	bg.settings.style = LayerData.Style.CROSS_STITCH
	var sl := Patterns.default_slot()
	sl.source = Patterns.Src.HATCHING
	sl.mode = 1
	sl.scale = 1.5
	sl.drives = 0
	sl.fine = true
	sl.fine_amount = 0.8
	var d := new_layer("Flow", func(l): l.kind = "direction")
	d.is_static = true
	app.perform("strokes", func():
		var arr := d.strokes_at(0)
		arr.append(DirStroke.make("field", "swirl_cw", PackedVector2Array([Vector2(170, 330), Vector2(230, 330)]), 220.0, 1.0))
		arr.append(DirStroke.make("arrow", "path", PackedVector2Array([Vector2(20, 60), Vector2(500, 120)]), 160.0, 1.0))
		arr.append(DirStroke.make("bezier", "path", PackedVector2Array([Vector2(300, 480), Vector2(360, 300), Vector2(440, 520), Vector2(500, 330)]), 140.0, 1.0))
		bg.settings.patterns = [sl]
		bg.settings.flow_layer = d.id
		bg.settings.flow_stamp_rot = true
		bg.settings.flow_patterns = true
		d.settings["dir"] = {"field_display": 1})
	app.dir_selected = 2


func shapes() -> void:
	var puzzle := Shape.builtin("Puzzle piece")
	var parsed := Svg.parse_file(ProjectSettings.globalize_path("res://tests/data/star.svg"))
	var star := Svg.to_stamp(parsed, "star")
	app.perform("shapes", func():
		app.project.shapes[puzzle.id] = puzzle
		app.project.shapes[star.id] = star
		app.project.register_shapes())
	var bg: LayerData = app.active_layer()
	app.change_layer_tiling(bg, "shape:" + puzzle.id, {})
	bg = app.active_layer()
	fill_layer(bg, func(c, p): return [8, 9, 10, 13, 14][(c.x * 3 + c.y * 2) % 5] if p.x < 300 else 0)
	app.perform("gap", func():
		bg.settings.gap_on = true
		bg.settings.gap = 0.08)
	var st := new_layer("stars", func(l):
		l.settings.style = LayerData.Style.SVG_STAMP
		l.settings.stamp_shape = star.id
		l.settings.dot_size = 0.95)
	fill_layer(st, func(c, p): return 6 if p.x > 300 else 0)
	main.open_shape_editor()
	main._shape_editor._select(puzzle.id)
	await get_tree().process_frame
	await get_tree().process_frame
	var w: Window = main._shape_editor
	await RenderingServer.frame_post_draw
	w.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("shape_editor.png"))
	w.hide()


func exports() -> void:
	await direction()
	var bg: LayerData = app.project.layers[0]
	app.set_active_layer(bg.id)
	app.perform("frames", func():
		bg.insert_frame(1, 0, 0)
		app.project.frame_count = 2
		app.project.frame_durations = PackedInt32Array([120, 120])
		app.project.display = {"noise_on": true, "noise": 0.2, "interlace_on": true})
	var dir := OS.get_environment("SHOT_DIR")
	for i in Exporter.FORMATS.size():
		var o := Exporter.default_options()
		o.format = i
		o.repeat = 2
		if Exporter.FORMATS[i].id == "field":
			app.set_active_layer(app.project.layers[1].id)
		var msg: String = await Exporter.write(main, main.hub, dir.path_join("export_" + Exporter.FORMATS[i].id), o)
		print("EXPORT ", Exporter.FORMATS[i].id, ": ", msg)
	var o2 := Exporter.default_options()
	o2.raw = true
	o2.scale = 2
	print("EXPORT raw: ", await Exporter.write(main, main.hub, dir.path_join("export_raw.png"), o2))


func presets() -> void:
	var bg: LayerData = app.active_layer()
	fill_layer(bg, func(c, p): return [16, 17, 18, 19, 6, 9, 10][int(p.x / 74 + p.y / 90) % 7])
	var by_name := {}
	for pr in Library.builtin_layer_presets():
		by_name[pr.name] = pr
	Library.apply_layer_preset(bg, by_name[OS.get_environment("PRESET") if OS.get_environment("PRESET") != "" else "Stained glass"])
