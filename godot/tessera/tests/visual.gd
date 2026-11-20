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
	for i in 24:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(name_ + ".png"))
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
