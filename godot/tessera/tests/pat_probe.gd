extends Node
func stats(img: Image) -> String:
	var f := img.get_data().to_float32_array()
	var mn := 1e9; var mx := -1e9; var s := 0.0
	for v in f:
		mn = minf(mn, v); mx = maxf(mx, v); s += v
	var row := ""
	for x in 16:
		row += "%.2f " % f[x]
	return "min %.3f max %.3f mean %.3f | first row: %s" % [mn, mx, s / f.size(), row]
func _ready() -> void:
	await get_tree().process_frame
	var t := TilingRegistry.create("square", 8.0, Vector2(512, 512), {})
	var cells := PackedByteArray(); cells.resize(t.cell_count()); cells.fill(5)
	var sl := Patterns.default_slot()
	sl.scale = 6.0
	print("fractal: ", stats(Patterns.cell_map(sl, t, cells, ProjectData.default_palette(), null)))
	sl.source = Patterns.Src.PERLIN
	print("perlin: ", stats(Patterns.cell_map(sl, t, cells, ProjectData.default_palette(), null)))
	var rd := Patterns.default_slot()
	rd.source = 0; rd.iterations = 1500; rd.scale = 2.0
	var r := Patterns.reaction_diffusion(rd, Vector2(512, 512), 8.0)
	print("rd raster ", r.get_size(), ": ", stats(r))
	get_tree().quit()
