extends SceneTree
## Run: godot --path . -s tests/test_core.gd  (needs a Vulkan device)

var failures := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok   ", msg)

func _initialize() -> void:
	await process_frame
	var gpu = root.get_node("Gpu")
	var canvas := Vector2(160, 128)
	var variants: Array = []
	for tid in TilingRegistry.ids():
		variants.append([tid, 0])
		var b := TilingRegistry.create(tid, 8.0, canvas, {})
		for m in OffsetTiling.modes_for(b):
			if m != 0:
				variants.append([tid, m])
	for v in variants:
		var id: String = "%s+off%d" % v
		var t := LayerData.make_tiling(v[0], TilingRegistry.default_params(v[0]), v[1], 0.37 if v[1] != 4 else 0.5, 8.0, canvas)
		# center -> cell round trip and neighbor symmetry
		var bad := 0
		for i in t.cell_count():
			var c := t.cell_of_index(i)
			if t.point_to_cell(t.cell_center(c)) != c:
				bad += 1
			for n in t.neighbors(c):
				if not t.neighbors(n).has(c):
					bad += 1
		check(bad == 0, "%s: center round-trip + neighbor symmetry (%d bad)" % [id, bad])
		# every canvas point maps into the grid (no gaps)
		var gaps := 0
		for y in range(0, int(canvas.y), 3):
			for x in range(0, int(canvas.x), 3):
				if not t.in_grid(t.point_to_cell(Vector2(x + 0.37, y + 0.61))):
					gaps += 1
		check(gaps == 0, "%s: canvas fully covered (%d uncovered samples)" % [id, gaps])
		# GPU resample identity == same cells (GLSL matches GDScript)
		var cells := PackedByteArray()
		cells.resize(t.cell_count())
		for i in cells.size():
			cells[i] = (i * 7 + 3) % 200
		var back: PackedByteArray = gpu.resample_cells(cells, t, t, Vector2.ZERO)
		var diff := 0
		for i in cells.size():
			if back[i] != cells[i]:
				diff += 1
		check(diff == 0, "%s: GPU identity resample matches (%d differ)" % [id, diff])
		# layer shader compiles
		var sh := ShaderBuilder.layer_shader(t)
		var rect := ColorRect.new()
		var mat := ShaderMaterial.new()
		mat.shader = sh
		rect.material = mat
		root.add_child(rect)
		var ov := ColorRect.new()
		var mat2 := ShaderMaterial.new()
		mat2.shader = ShaderBuilder.overlay_shader(t)
		ov.material = mat2
		root.add_child(ov)
	var cb := ColorRect.new()
	var m3 := ShaderMaterial.new()
	m3.shader = ShaderBuilder.compositor_shader(16)
	cb.material = m3
	root.add_child(cb)
	await process_frame
	await process_frame
	# palette snap
	var img := Image.create(4, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.9, 0.1, 0.1))
	img.set_pixel(1, 0, Color(0.1, 0.1, 0.85))
	img.set_pixel(2, 0, Color(0.5, 0.5, 0.5))
	img.set_pixel(3, 0, Color(0, 0, 0, 0))
	var pal := PackedColorArray([Color.RED, Color.BLUE, Color.WHITE, Color.BLACK])
	var out: Image = gpu.palette_snap(img, pal, false, 0.5)
	check(out.get_pixel(0, 0).is_equal_approx(Color.RED) and out.get_pixel(1, 0).is_equal_approx(Color.BLUE), "palette snap nearest in OKLab")
	check(out.get_pixel(3, 0).a == 0.0, "palette snap keeps transparency")
	var u: Dictionary = gpu.unique_colors(img)
	check(u.colors.size() == 3 and u.colors[0].is_equal_approx(img.get_pixel(0, 0)), "unique colors in order: %s" % [u.colors])
	var big := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			big.set_pixel(x, y, Color(1, 0.2, 0.1) if x < 32 else Color(0.1, 0.3, 1.0))
	var red: PackedColorArray = gpu.reduce_colors(big, 2)
	check(red.size() == 2, "k-means reduce to 2: %s" % [red])
	# resample square -> hex keeps a filled canvas mostly filled
	var sq := TilingRegistry.create("square", 8.0, canvas, {})
	var hx := TilingRegistry.create("hex", 8.0, canvas, {})
	var full := PackedByteArray()
	full.resize(sq.cell_count())
	full.fill(5)
	var hres: PackedByteArray = gpu.resample_cells(full, sq, hx, Vector2.ZERO)
	check(hres.count(5) > hx.cell_count() * 0.7, "square->hex resample fills (%d/%d)" % [hres.count(5), hx.cell_count()])
	# project round trip
	var p := ProjectData.create_default()
	p.layers[0].frames[0][5] = 3
	var d := ProjectIO.to_dict(p)
	var back2: Dictionary = ProjectIO.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back2.has("project") and back2.project.layers[0].frames[0][5] == 3, "project JSON round trip")
	var old := {"format_version": 1, "width": 10, "height": 12, "cell": 4, "palette": ["ff0000"], "layers": [{"name": "a", "blend_mode": "multiply", "frames": []}]}
	var mig: Dictionary = ProjectIO.from_dict(old)
	check(mig.project.canvas_cells == Vector2i(10, 12) and mig.project.layers[0].blend_mode == 1, "v1 -> v2 migration")
	var newer: Dictionary = ProjectIO.from_dict({"format_version": 99, "palette": [], "layers": []})
	check(newer.warnings.size() == 1, "newer-version file warns instead of failing")
	print("FAILURES: ", failures)
	quit(failures)
