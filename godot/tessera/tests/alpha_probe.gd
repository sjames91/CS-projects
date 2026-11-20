extends Node
func _ready() -> void:
	var main: Control = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 8:
		await get_tree().process_frame
	var cv: CanvasView = main.canvas
	for mode in [true, false]:
		get_node("/root/App").set_view("render_on", mode)
		for i in 6:
			await get_tree().process_frame
		var img := cv.view.get_texture().get_image()
		var c := cv.canvas_to_screen(Vector2(100, 100))
		print("render_on=", mode, " vp pixel=", img.get_pixel(int(c.x), int(c.y)), " format=", img.get_format())
	get_tree().quit()
