extends Node
## Direction layer -> flow field -> a layer following it. Saves flow.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var main: Control = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 6:
		await get_tree().process_frame
	var app = get_node("/root/App")
	var cv: CanvasView = main.canvas
	var bg: LayerData = app.active_layer()
	bg.settings.style = LayerData.Style.CROSS_STITCH
	bg.settings.dot_size = 1.0
	bg.settings.jitter_on = true
	bg.settings.jitter_source = 1
	bg.settings.jitter_rot = 1.0
	bg.settings.jitter_pos = 0.3
	var t: Tiling = app.active_tiling()
	var data := bg.cells(0)
	for i in data.size():
		data[i] = 7 + (i / t.grid.x) % 4
	app.layer_cells_changed.emit(bg.id)
	app.perform("dir", func():
		var d: LayerData = app.project.add_layer("Flow", "direction")
		var circle := PackedVector2Array()
		for k in 41:
			var a := TAU * k / 40.0
			circle.append(Vector2(256, 256) + Vector2(cos(a), sin(a)) * 170.0)
		d.strokes.append(circle)
		d.strokes.append(PackedVector2Array([Vector2(20, 20), Vector2(140, 60), Vector2(250, 30)]))
		bg.settings.flow_layer = d.id
		app.active_layer_id = d.id)
	cv.fit_view()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("flow.png"))
	get_tree().quit()
