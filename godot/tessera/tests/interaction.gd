extends Node
## Drives the editor with real mouse events on the canvas, then checks state.

var failures := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok   ", msg)


func mouse(cv: CanvasView, pos: Vector2, button: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.button_index = button
	e.pressed = pressed
	e.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	cv._gui_input(e)


func move(cv: CanvasView, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	cv._gui_input(e)


func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var main: Control = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 6:
		await get_tree().process_frame
	var app = get_node("/root/App")
	var cv: CanvasView = main.canvas
	cv.fit_view()
	var l: LayerData = app.active_layer()
	var t: Tiling = app.active_tiling()
	# Left drag paints, through the real input path.
	app.set_tool("pencil")
	app.set_color(8)
	var a := cv.canvas_to_screen(Vector2(40, 40))
	var b := cv.canvas_to_screen(Vector2(200, 40))
	mouse(cv, a, MOUSE_BUTTON_LEFT, true)
	for i in 21:
		move(cv, a.lerp(b, i / 20.0))
	mouse(cv, b, MOUSE_BUTTON_LEFT, false)
	var row := 0
	for x in range(5, 25):
		if l.cells(0)[t.index(Vector2i(x, 5))] == 8:
			row += 1
	check(row == 20, "left drag painted a continuous row (%d/20 cells)" % row)
	check(app.undo.undo_name() == "Draw", "one stroke = one undo step")
	# Right drag erases even with another tool selected.
	app.set_tool("ellipse")
	var c := cv.canvas_to_screen(Vector2(100, 40))
	mouse(cv, c, MOUSE_BUTTON_RIGHT, true)
	move(cv, c + Vector2(30, 0))
	mouse(cv, c + Vector2(30, 0), MOUSE_BUTTON_RIGHT, false)
	check(l.cells(0)[t.index(Vector2i(12, 5))] == 0, "right drag erases regardless of tool")
	# Wheel zoom keeps the point under the cursor fixed.
	var anchor := cv.canvas_to_screen(Vector2(77, 91))
	var before := cv.screen_to_canvas(anchor)
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	w.position = anchor
	cv._gui_input(w)
	check(cv.screen_to_canvas(anchor).distance_to(before) < 0.01, "wheel zoom centered on cursor")
	cv.fit_view()
	# Mirror both: one click -> 4 cells.
	app.set_view("mirror", 3)
	app.set_tool("pencil")
	app.set_color(12)
	var p := cv.canvas_to_screen(Vector2(20, 300))
	mouse(cv, p, MOUSE_BUTTON_LEFT, true)
	mouse(cv, p, MOUSE_BUTTON_LEFT, false)
	var px: Vector2 = app.project.canvas_px()
	var hits := 0
	for q in [Vector2(20, 300), Vector2(px.x - 20, 300), Vector2(20, px.y - 300), Vector2(px.x - 20, px.y - 300)]:
		if l.cells(0)[t.index(t.point_to_cell(q))] == 12:
			hits += 1
	check(hits == 4, "mirror both paints 4 cells (%d)" % hits)
	app.set_view("mirror", 0)
	# Flood fill (contiguous) on a fresh hex layer stays inside a ring.
	app.perform("hex", func():
		var hl: LayerData = app.project.add_layer("Hex")
		hl.tiling_id = "hex"
		app.active_layer_id = hl.id)
	var hl: LayerData = app.active_layer()
	var ht: Tiling = app.active_tiling()
	app.set_tool("ellipse")
	app.tool_opts.filled = false
	app.set_color(2)
	var e0 := cv.canvas_to_screen(Vector2(260, 260))
	var e1 := cv.canvas_to_screen(Vector2(420, 420))
	mouse(cv, e0, MOUSE_BUTTON_LEFT, true)
	move(cv, e1)
	mouse(cv, e1, MOUSE_BUTTON_LEFT, false)
	app.set_tool("fill")
	app.set_color(5)
	var fc := cv.canvas_to_screen(Vector2(340, 340))
	mouse(cv, fc, MOUSE_BUTTON_LEFT, true)
	mouse(cv, fc, MOUSE_BUTTON_LEFT, false)
	var inside: int = hl.cells(0)[ht.index(ht.point_to_cell(Vector2(340, 340)))]
	var outside: int = hl.cells(0)[ht.index(ht.point_to_cell(Vector2(100, 450)))]
	check(inside == 5 and outside == 0, "hex flood fill stays inside the ring (in=%d out=%d)" % [inside, outside])
	# Selection + rotate by the tiling step (60deg on hex) keeps cell count.
	app.set_tool("wand")
	mouse(cv, fc, MOUSE_BUTTON_LEFT, true)
	mouse(cv, fc, MOUSE_BUTTON_LEFT, false)
	check(app.has_selection(), "magic wand selects")
	var count_before: int = hl.cells(0).count(5)
	SelectionOps.transform("rot_cw")
	var count_after: int = hl.cells(0).count(5)
	check(abs(count_after - count_before) <= 2, "hex rotate 60° keeps cells (%d -> %d)" % [count_before, count_after])
	SelectionOps.copy()
	app.clear_selection()
	# Colour-aware rounding + tile preview screenshot.
	app.perform("square2", func():
		var sl: LayerData = app.project.add_layer("Rounded")
		sl.settings.rounding_on = true
		sl.settings.rounding = 0.9
		sl.settings.rounding_color_aware = true
		sl.settings.rounding_inner = true
		app.active_layer_id = sl.id)
	app.set_tool("rect")
	app.tool_opts.filled = true
	for spec in [[Vector2(300, 40), Vector2(460, 200), 14], [Vector2(360, 100), Vector2(500, 240), 9], [Vector2(330, 150), Vector2(380, 230), 0]]:
		app.set_color(spec[2] if spec[2] > 0 else 1)
		var s0 := cv.canvas_to_screen(spec[0])
		var s1 := cv.canvas_to_screen(spec[1])
		var btn := MOUSE_BUTTON_LEFT if spec[2] > 0 else MOUSE_BUTTON_RIGHT
		mouse(cv, s0, btn, true)
		move(cv, s1)
		mouse(cv, s1, btn, false)
	cv.zoom = 3.0
	cv.center_on(Vector2(400, 140))
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("rounded.png"))
	app.set_view("tile_preview", true)
	cv.fit_view()
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("tiled.png"))
	app.set_view("tile_preview", false)
	# Save -> load round trip through the real menu functions.
	var path := out.path_join("roundtrip.tessera")
	main.save_to(path)
	var snapshot: PackedByteArray = app.active_layer().cells(0).duplicate()
	var nlayers: int = app.project.layers.size()
	main.open_file(path)
	await get_tree().process_frame
	check(app.project.layers.size() == nlayers and app.project.layers.back().cells(0) == snapshot and app.project.layers.back().settings.rounding_color_aware == true, "save + load round trip")
	# Canvas resize anchored bottom-right keeps content aligned.
	var bl: LayerData = app.project.layers[0]
	var bt: Tiling = app.tiling_of(bl)
	var v_before: int = bl.cells(0)[bt.index(Vector2i(10, 5))]
	app.resize_canvas(Vector2i(80, 70), 8, Vector2(1, 1))
	var bt2: Tiling = app.tiling_of(bl)
	check(bl.cells(0)[bt2.index(Vector2i(26, 11))] == v_before and v_before != 0, "resize with anchor shifts content by (16, 6) cells")
	app.do_undo()
	check(app.project.canvas_cells == Vector2i(64, 64), "resize is undoable")
	# Presets apply settings only, as one undo step.
	var pl: LayerData = app.project.layers[0]
	var cells_before: PackedByteArray = pl.cells(0).duplicate()
	var mosaic: Dictionary = Library.builtin_layer_presets().filter(func(x): return x.name == "Mosaic")[0]
	Library.apply_layer_preset(pl, mosaic)
	check(int(pl.setting("style")) == LayerData.Style.MOSAIC and pl.cells(0) == cells_before, "layer preset changes settings, not cells")
	var puzzle_p: Dictionary = Library.builtin_layer_presets().filter(func(x): return x.name == "Puzzle")[0]
	Library.apply_layer_preset(pl, puzzle_p)
	check(pl.tiling_id.begins_with("shape:") and app.project.shapes.has(pl.tiling_id.substr(6)), "shape preset embeds its shape in the project")
	app.do_undo()
	check(pl.tiling_id == "square" and pl.cells(0) == cells_before, "preset is one undo step")
	Library.add("layer", Library.layer_preset_from(pl, "test preset"))
	Library.load_user()
	check(Library.items("layer").back().name == "test preset", "user preset saved to the library folder and reloaded")
	Library.remove("layer", Library.items("layer").size() - 1)
	# Flatten / Apply bakes visibility into cells (explicit action only).
	var hide_all := Patterns.default_slot()
	hide_all.source = Patterns.Src.VALUE_NOISE
	hide_all.drives = Patterns.Drive.VISIBILITY
	hide_all.visibility = 1.1
	app.perform("pat", func(): pl.settings.patterns = [hide_all])
	check(pl.cells(0) == cells_before, "patterns never change cells by themselves")
	main.hub.flatten_patterns(pl)
	check(pl.cells(0).count(0) == pl.cells(0).size() and int(pl.settings.patterns[0].drives) == 0, "Flatten/Apply bakes visibility and clears the drive")
	app.do_undo()
	check(pl.cells(0) == cells_before, "Flatten/Apply is undoable")
	# Settings tab screenshot.
	var tabs: TabContainer = main.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 1
	app.set_active_layer(app.project.layers.back().id)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("settings.png"))
	print("FAILURES: ", failures)
	get_tree().quit(failures)
