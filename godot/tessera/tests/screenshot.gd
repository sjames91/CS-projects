extends Node
## Opens the editor, paints some cells through the real tool code on several
## layers/tilings, and saves screenshots. Run under a real GPU / lavapipe:
##   godot --path . -s tests/screenshot.gd -- out_dir

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	var main: Control = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 5:
		await get_tree().process_frame
	var app = get_node("/root/App")
	var cv: CanvasView = main.canvas
	var p: ProjectData = app.project
	# Background: flat squares
	var bg: LayerData = app.active_layer()
	var tc := ToolController.new()
	app.tool_opts.filled = true
	app.set_color(3)
	app.set_tool("rect")
	tc.press(Vector2(0, 0), false, {})
	tc.drag(Vector2(511, 511), {})
	tc.release(Vector2(511, 511), {})
	app.set_color(17)
	app.set_tool("ellipse")
	tc.press(Vector2(80, 80), false, {})
	tc.drag(Vector2(430, 430), {})
	tc.release(Vector2(430, 430), {})
	# Hex layer with dots + gap
	app.perform("add", func():
		var l: LayerData = p.add_layer("Hex dots")
		l.tiling_id = "hex"
		l.settings.style = LayerData.Style.LED
		l.blend_mode = LayerData.Blend.SCREEN
		app.active_layer_id = l.id)
	app.set_color(10)
	app.set_tool("pencil")
	app.tool_opts.brush = 5
	tc.press(Vector2(60, 300), false, {})
	for x in range(60, 460, 6):
		tc.drag(Vector2(x, 300 + sin(x * 0.03) * 80.0), {})
	tc.release(Vector2(460, 300), {})
	# Triangle layer with rounding (colour-aware) and a fill
	app.perform("add", func():
		var l: LayerData = p.add_layer("Triangles")
		l.tiling_id = "triangle"
		l.settings.rounding_on = true
		l.settings.gap_on = true
		l.settings.gap = 0.2
		app.active_layer_id = l.id)
	app.set_color(13)
	app.set_tool("ellipse")
	app.tool_opts.brush = 1
	tc.press(Vector2(20, 20), false, {})
	tc.drag(Vector2(200, 200), {})
	tc.release(Vector2(200, 200), {})
	# Voronoi layer, mosaic style
	app.perform("add", func():
		var l: LayerData = p.add_layer("Voronoi")
		l.tiling_id = "voronoi"
		l.tiling_params = {"jitter": 0.9, "seed": 3}
		l.settings.style = LayerData.Style.MOSAIC
		app.active_layer_id = l.id)
	app.set_color(19)
	app.set_tool("rect")
	app.tool_opts.filled = true
	tc.press(Vector2(330, 20), false, {})
	tc.drag(Vector2(500, 180), {})
	tc.release(Vector2(500, 180), {})
	app.set_color(8)
	app.set_tool("pencil")
	app.tool_opts.brush = 3
	tc.press(Vector2(340, 100), false, {})
	tc.drag(Vector2(490, 100), {})
	tc.release(Vector2(490, 100), {})
	# Diamond layer with CRT
	app.perform("add", func():
		var l: LayerData = p.add_layer("Diamond CRT")
		l.tiling_id = "diamond"
		l.settings.style = LayerData.Style.CRT
		l.settings.scan_on = true
		l.settings.beam_on = true
		app.active_layer_id = l.id)
	app.set_color(9)
	app.set_tool("rect")
	tc.press(Vector2(330, 360), false, {})
	tc.drag(Vector2(500, 500), {})
	tc.release(Vector2(500, 500), {})
	app.set_active_layer(bg.id)
	app.set_tool("select_rect")
	tc.press(Vector2(100, 100), false, {})
	tc.drag(Vector2(220, 180), {})
	tc.release(Vector2(220, 180), {})
	cv.fit_view()
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("editor.png"))
	# Raw mode
	app.set_view("render_on", false)
	app.set_active_layer(p.layers[2].id)
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("editor_raw.png"))
	app.set_view("render_on", true)
	# Export with palette lock + dither
	p.palette_lock = {"enabled": true, "dither": true, "strength": 0.5}
	var img: Image = await main.render_frame_image(0, 1)
	img.save_png(out.path_join("export_locked.png"))
	# Zoomed in
	cv.zoom = 6.0
	cv.center_on(Vector2(110, 110))
	app.set_active_layer(p.layers[2].id)
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("editor_zoom.png"))
	# undo everything back to the start works
	var steps := 0
	while app.undo.can_undo():
		app.do_undo()
		steps += 1
	print("undo steps: ", steps, " layers now: ", p.layers.size() if app.project == p else app.project.layers.size())
	get_tree().quit()
