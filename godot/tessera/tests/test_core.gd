extends Node
## Run: godot --path . res://tests/test_core.tscn  (needs a Vulkan device)

var failures := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok   ", msg)

func _ready() -> void:
	await get_tree().process_frame
	var gpu = get_node("/root/Gpu")
	var root := get_tree().root
	var canvas := Vector2(160, 128)
	for nm in Shape.BUILTINS:
		var sh := Shape.builtin(nm)
		sh.id = nm.to_lower().replace(" ", "_")
		TilingRegistry.register("shape:" + sh.id, func(): return ShapeTiling.new(sh))
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
		# layer shader compiles (plain + one offset variant per tiling; every
		# variant would compile ~100 large shaders on a software GPU)
		if v[1] > 1:
			continue
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
	await get_tree().process_frame
	await get_tree().process_frame
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
	var dl := p.add_layer("Dir", "direction")
	dl.strokes_at(0).append(DirStroke.make("bezier", "path", PackedVector2Array([Vector2(1, 2), Vector2(3, 4), Vector2(5, 6), Vector2(7, 8)]), 12.0, 0.5))
	dl.strokes_at(0).append(DirStroke.make("field", "swirl_ccw", PackedVector2Array([Vector2(50, 50), Vector2(60, 50)]), 40.0, 1.0))
	var back3: Dictionary = ProjectIO.from_dict(JSON.parse_string(JSON.stringify(ProjectIO.to_dict(p))))
	var bl: LayerData = back3.project.layers.back()
	check(bl.is_direction() and bl.strokes_at(0).size() == 2 and bl.strokes_at(0)[0].points[3] == Vector2(7, 8) and bl.strokes_at(0)[1].type == "swirl_ccw", "direction strokes round trip")
	var v2 := {"format_version": 2, "canvas": {"cells": [8, 8], "cell_size": 4}, "palette": [], "layers": [{"name": "d", "kind": "direction", "strokes": [[0, 0, 10, 10]], "frames": []}]}
	var m2: Dictionary = ProjectIO.from_dict(v2)
	check(m2.project.layers[0].strokes_at(0).size() == 1 and m2.project.layers[0].strokes_at(0)[0].points[1] == Vector2(10, 10), "v2 -> v3 stroke migration")
	# SVG parsing: relative commands, H/V, quadratic, smooth cubic, arc, close.
	var paths := Svg.parse_d("m10 10 h20 v20 q-10 10 -20 0 z M100 100 C110 90 130 90 140 100 S170 110 180 100 A20 20 0 0 1 220 100")
	check(paths.size() == 2 and paths[0].closed and not paths[1].closed, "svg path subpaths / close (%d)" % paths.size())
	check((paths[0].points.size() - 1) % 3 == 0 and (paths[1].points.size() - 1) % 3 == 0, "svg paths are cubic chains")
	check(paths[1].points[paths[1].points.size() - 1].distance_to(Vector2(220, 100)) < 0.01, "svg arc ends at its endpoint")
	var arc_mid: Vector2 = paths[1].points[paths[1].points.size() - 4]
	check(absf(arc_mid.distance_to(Vector2(200, 100)) - 20.0) < 0.5, "svg arc stays on its circle")
	var shp := Shape.builtin("Lizard interlock")
	var re := Svg.parse_string(Svg.shape_svg(shp))
	check(re.paths.size() == 1 and re.paths[0].closed, "shape -> svg -> geometry round trip")
	var fitted := Svg.to_tiling(Svg.parse_string('<svg><circle cx="0" cy="0" r="10"/></svg>'), "hexagon", "c")
	var ok_pair := true
	for e in 3:
		var a := Shape.edge_chain(fitted, e)
		var b := Shape.edge_chain(fitted, e + 3)
		var t := Shape.translation(fitted, e)
		for k in a.size():
			if a[k].distance_to(b[b.size() - 1 - k] - t) > 1e-4:
				ok_pair = false
	check(ok_pair, "imported SVG fitted to a tile keeps opposite edges paired")
	# GIF / APNG encoders produce well-formed files.
	var fa := Image.create(6, 4, false, Image.FORMAT_RGBA8)
	fa.fill(Color.RED)
	var fb := Image.create(6, 4, false, Image.FORMAT_RGBA8)
	fb.fill(Color.BLUE)
	var g := Encoders.gif([fa, fb], [10, 10], PackedColorArray([Color.RED, Color.BLUE]))
	check(g.slice(0, 6).get_string_from_ascii() == "GIF89a" and g[g.size() - 1] == 0x3B, "GIF header and trailer")
	var idx := Encoders.index_image(fb, PackedColorArray([Color.RED, Color.BLUE]))
	check(idx.size() == 24 and idx.count(1) == 24, "GIF indices from GPU OKLab match")
	var ap := Encoders.apng([fa, fb], [100, 100])
	var back := Image.new()
	check(back.load_png_from_buffer(ap) == OK and back.get_pixel(0, 0).is_equal_approx(Color.RED), "APNG opens as a PNG showing frame 1")
	check(Encoders._crc32("IEND".to_ascii_buffer()) == 0xAE426082, "PNG CRC32")
	var newer: Dictionary = ProjectIO.from_dict({"format_version": 99, "palette": [], "layers": []})
	check(newer.warnings.size() == 1, "newer-version file warns instead of failing")
	print("FAILURES: ", failures)
	get_tree().quit(failures)
