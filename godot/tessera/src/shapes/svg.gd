class_name Svg
extends RefCounted
## SVG geometry import / export. Only geometry is read (fills, strokes and
## styles are ignored). Every path becomes a cubic chain (3n+1 points).


## Returns {paths: [{points: PackedVector2Array, closed: bool}], bounds: Rect2}
static func parse_file(path: String) -> Dictionary:
	var x := XMLParser.new()
	if x.open(path) != OK:
		return {"paths": [], "bounds": Rect2(), "error": "Cannot open " + path}
	return _parse(x)


static func parse_string(text: String) -> Dictionary:
	var x := XMLParser.new()
	if x.open_buffer(text.to_utf8_buffer()) != OK:
		return {"paths": [], "bounds": Rect2(), "error": "Not valid SVG"}
	return _parse(x)


static func _attr(x: XMLParser, n: String, def := 0.0) -> float:
	return float(x.get_named_attribute_value_safe(n)) if x.has_attribute(n) else def


static func _parse(x: XMLParser) -> Dictionary:
	var paths: Array = []
	while x.read() == OK:
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match x.get_node_name():
			"path":
				paths.append_array(parse_d(x.get_named_attribute_value_safe("d")))
			"rect":
				var r := Rect2(_attr(x, "x"), _attr(x, "y"), _attr(x, "width"), _attr(x, "height"))
				paths.append(_poly_path([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)], true))
			"circle":
				paths.append(_ellipse(Vector2(_attr(x, "cx"), _attr(x, "cy")), Vector2.ONE * _attr(x, "r")))
			"ellipse":
				paths.append(_ellipse(Vector2(_attr(x, "cx"), _attr(x, "cy")), Vector2(_attr(x, "rx"), _attr(x, "ry"))))
			"line":
				paths.append(_poly_path([Vector2(_attr(x, "x1"), _attr(x, "y1")), Vector2(_attr(x, "x2"), _attr(x, "y2"))], false))
			"polygon", "polyline":
				var nums := _numbers(x.get_named_attribute_value_safe("points"))
				var pts: Array = []
				for i in range(0, nums.size() - 1, 2):
					pts.append(Vector2(nums[i], nums[i + 1]))
				if pts.size() >= 2:
					paths.append(_poly_path(pts, x.get_node_name() == "polygon"))
	var b := Rect2()
	var first := true
	for p in paths:
		for v in p.points:
			if first:
				b = Rect2(v, Vector2.ZERO)
				first = false
			else:
				b = b.expand(v)
	return {"paths": paths, "bounds": b}


static func _line(a: Vector2, b: Vector2) -> Array:
	return [a.lerp(b, 1.0 / 3.0), a.lerp(b, 2.0 / 3.0), b]


static func _poly_path(pts: Array, closed: bool) -> Dictionary:
	var ch := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		ch.append_array(_line(pts[i - 1], pts[i]))
	if closed and pts.size() > 2:
		ch.append_array(_line(pts[pts.size() - 1], pts[0]))
	return {"points": ch, "closed": closed}


static func _ellipse(c: Vector2, r: Vector2) -> Dictionary:
	var k := 0.5522847498
	var pts := PackedVector2Array([c + Vector2(r.x, 0)])
	var quads := [[Vector2(r.x, 0), Vector2(0, r.y)], [Vector2(0, r.y), Vector2(-r.x, 0)], [Vector2(-r.x, 0), Vector2(0, -r.y)], [Vector2(0, -r.y), Vector2(r.x, 0)]]
	for q in quads:
		var a: Vector2 = q[0]
		var b: Vector2 = q[1]
		pts.append_array([c + a + b * k, c + b + a * k, c + b])
	return {"points": pts, "closed": true}


static func _numbers(s: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var re := RegEx.new()
	re.compile("[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?")
	for m in re.search_all(s):
		out.append(float(m.get_string()))
	return out


## Path data -> list of chains (one per subpath).
static func parse_d(d: String) -> Array:
	var re := RegEx.new()
	re.compile("[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?")
	var toks: Array = re.search_all(d).map(func(m): return m.get_string())
	var out: Array = []
	var cur := PackedVector2Array()
	var pos := Vector2.ZERO
	var start := Vector2.ZERO
	var last_c := Vector2.ZERO  # last cubic control (for S)
	var last_q := Vector2.ZERO  # last quadratic control (for T)
	var prev_cmd := ""
	var cmd := ""
	var i := 0
	while i < toks.size():
		var t: String = toks[i]
		if t.length() == 1 and "MmLlHhVvCcSsQqTtAaZz".contains(t):
			cmd = t
			i += 1
			if cmd == "Z" or cmd == "z":
				if pos != start:
					cur.append_array(_line(pos, start))
				pos = start
				_flush(out, cur, true)
				cur = PackedVector2Array()
				prev_cmd = cmd
				continue
		if cmd == "":
			break
		var rel := cmd == cmd.to_lower()
		var o := pos if rel else Vector2.ZERO
		var n := func(k: int) -> float: return float(toks[i + k]) if i + k < toks.size() else 0.0
		match cmd.to_upper():
			"M":
				_flush(out, cur, false)
				pos = o + Vector2(n.call(0), n.call(1))
				start = pos
				cur = PackedVector2Array([pos])
				i += 2
				cmd = "l" if rel else "L"  # implicit lineto
			"L":
				var p := o + Vector2(n.call(0), n.call(1))
				cur.append_array(_line(pos, p))
				pos = p
				i += 2
			"H":
				var p := Vector2((pos.x if rel else 0.0) + n.call(0), pos.y)
				cur.append_array(_line(pos, p))
				pos = p
				i += 1
			"V":
				var p := Vector2(pos.x, (pos.y if rel else 0.0) + n.call(0))
				cur.append_array(_line(pos, p))
				pos = p
				i += 1
			"C":
				var c1 := o + Vector2(n.call(0), n.call(1))
				var c2 := o + Vector2(n.call(2), n.call(3))
				var p := o + Vector2(n.call(4), n.call(5))
				cur.append_array([c1, c2, p])
				last_c = c2
				pos = p
				i += 6
			"S":
				var c1 := pos * 2.0 - last_c if prev_cmd.to_upper() in ["C", "S"] else pos
				var c2 := o + Vector2(n.call(0), n.call(1))
				var p := o + Vector2(n.call(2), n.call(3))
				cur.append_array([c1, c2, p])
				last_c = c2
				pos = p
				i += 4
			"Q", "T":
				var q: Vector2
				var p: Vector2
				if cmd.to_upper() == "Q":
					q = o + Vector2(n.call(0), n.call(1))
					p = o + Vector2(n.call(2), n.call(3))
					i += 4
				else:
					q = pos * 2.0 - last_q if prev_cmd.to_upper() in ["Q", "T"] else pos
					p = o + Vector2(n.call(0), n.call(1))
					i += 2
				cur.append_array([pos + (q - pos) * 2.0 / 3.0, p + (q - p) * 2.0 / 3.0, p])
				last_q = q
				pos = p
			"A":
				var p := o + Vector2(n.call(5), n.call(6))
				cur.append_array(_arc(pos, Vector2(n.call(0), n.call(1)), n.call(2), n.call(3) != 0.0, n.call(4) != 0.0, p))
				pos = p
				i += 7
			_:
				i += 1
		if cur.is_empty():
			cur = PackedVector2Array([pos])
		prev_cmd = cmd
	_flush(out, cur, false)
	return out


static func _flush(out: Array, cur: PackedVector2Array, closed: bool) -> void:
	if cur.size() >= 4:
		out.append({"points": cur, "closed": closed})


## SVG elliptical arc -> cubic segments (<= 90 degrees each).
static func _arc(p0: Vector2, r: Vector2, rot_deg: float, large: bool, sweep: bool, p1: Vector2) -> Array:
	if r.x == 0 or r.y == 0 or p0 == p1:
		return _line(p0, p1)
	r = r.abs()
	var phi := deg_to_rad(rot_deg)
	var dp := (p0 - p1) * 0.5
	var x1 := dp.rotated(-phi)
	var lam := (x1.x * x1.x) / (r.x * r.x) + (x1.y * x1.y) / (r.y * r.y)
	if lam > 1.0:
		r *= sqrt(lam)
	var num := r.x * r.x * r.y * r.y - r.x * r.x * x1.y * x1.y - r.y * r.y * x1.x * x1.x
	var den := r.x * r.x * x1.y * x1.y + r.y * r.y * x1.x * x1.x
	var co := sqrt(maxf(num / den, 0.0)) * (-1.0 if large == sweep else 1.0)
	var cp := Vector2(r.x * x1.y / r.y, -r.y * x1.x / r.x) * co
	var c := cp.rotated(phi) + (p0 + p1) * 0.5
	var a1 := Vector2((x1.x - cp.x) / r.x, (x1.y - cp.y) / r.y).angle()
	var da := wrapf(Vector2((-x1.x - cp.x) / r.x, (-x1.y - cp.y) / r.y).angle() - a1, -PI, PI)
	if sweep and da < 0:
		da += TAU
	elif not sweep and da > 0:
		da -= TAU
	var segs := int(ceil(absf(da) / (PI * 0.5)))
	var out: Array = []
	var step := da / segs
	var k := 4.0 / 3.0 * tan(step / 4.0)
	for s in segs:
		var t0 := a1 + step * s
		var t1 := t0 + step
		var e0 := Vector2(cos(t0), sin(t0))
		var e1 := Vector2(cos(t1), sin(t1))
		var q0 := c + Vector2(r.x * e0.x, r.y * e0.y).rotated(phi)
		var q1 := c + Vector2(r.x * e1.x, r.y * e1.y).rotated(phi)
		var d0 := Vector2(-r.x * e0.y, r.y * e0.x).rotated(phi)
		var d1 := Vector2(-r.x * e1.y, r.y * e1.x).rotated(phi)
		out.append_array([q0 + d0 * k, q1 - d1 * k, q1])
	return out


# ---- export -------------------------------------------------------------------

static func chain_d(pts: PackedVector2Array, closed: bool, scale := 1.0, off := Vector2.ZERO) -> String:
	if pts.is_empty():
		return ""
	var f := func(v: Vector2) -> String: return "%.3f %.3f" % [v.x * scale + off.x, v.y * scale + off.y]
	var s: String = "M " + f.call(pts[0])
	var i := 1
	while i + 2 < pts.size():
		s += " C %s, %s, %s" % [f.call(pts[i]), f.call(pts[i + 1]), f.call(pts[i + 2])]
		i += 3
	return s + (" Z" if closed else "")


static func shape_svg(sh: Dictionary) -> String:
	var body := ""
	if sh.kind == "tiling":
		body = '<path d="%s" fill="#444" stroke="none"/>' % chain_d(Shape.outline_chain(sh), true, 100.0, Vector2(150, 150))
	else:
		var d := ""
		for p in sh.paths:
			d += chain_d(PackedVector2Array(p.points), p.get("closed", true), 200.0, Vector2(150, 150)) + " "
		body = '<path d="%s" fill="#444" fill-rule="evenodd"/>' % d
	return '<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300" width="300" height="300">\n<title>%s</title>\n%s\n</svg>\n' % [sh.name.xml_escape(), body]


## Fit imported paths into a unit box centered on the origin (stamp shape).
static func to_stamp(parsed: Dictionary, name_: String) -> Dictionary:
	var b: Rect2 = parsed.bounds
	var s := 1.0 / maxf(maxf(b.size.x, b.size.y), 1e-6)
	var c := b.get_center()
	var paths: Array = []
	for p in parsed.paths:
		var pts: Array = []
		for v in p.points:
			pts.append((v - c) * s)
		paths.append({"points": pts, "closed": p.closed})
	return {"id": Shape.new_id(), "name": name_, "kind": "stamp", "paths": paths}


## Fit an imported outline onto a base tile so it tiles: each base edge is
## sampled by casting rays from the center to the outline; opposite edges
## are averaged into exact copies (pairing enforced).
static func to_tiling(parsed: Dictionary, base: String, name_: String, samples := 6) -> Dictionary:
	var sh := Shape.new_tiling(base, name_)
	var stamp := to_stamp(parsed, name_)
	var poly := PackedVector2Array()
	for p in stamp.paths:
		poly.append_array(Shape.flatten_chain(PackedVector2Array(p.points), 8))
	if poly.size() < 3:
		return sh
	# Scale the outline so its average radius matches the tile's.
	var tile_r := 0.0
	for i in Shape.corner_count(sh):
		tile_r += Shape.corner(sh, i).length() * 0.85
	tile_r /= Shape.corner_count(sh)
	var out_r := 0.0
	for v in poly:
		out_r += v.length()
	out_r /= poly.size()
	var k := tile_r / maxf(out_r, 1e-6)
	for i in poly.size():
		poly[i] *= k
	var h: int = sh.corners.size()
	for e in h:
		var offs: Array = []
		for si in samples:
			var t := (si + 1.0) / (samples + 1.0)
			var n1 := _ray_offset(sh, e, t, poly)
			# Paired edge at the same parameter (it is edge e translated).
			var n2 := _ray_offset(sh, e + h, 1.0 - t, poly)
			offs.append(clampf((n1 - n2) * 0.5, -0.4, 0.4))
		var chain: Array = []
		var anchors: Array = []
		for si in samples:
			anchors.append(Vector2((si + 1.0) / (samples + 1.0), offs[si]))
		var all := [Vector2(0, 0)] + anchors + [Vector2(1, 0)]
		chain.append(all[0].lerp(all[1], 1.0 / 3.0))
		for ai in range(1, all.size() - 1):
			var tan: Vector2 = (all[ai + 1] - all[ai - 1]) / 6.0
			chain.append_array([all[ai] - tan, all[ai], all[ai] + tan])
		chain.append(all[all.size() - 1].lerp(all[all.size() - 2], 1.0 / 3.0))
		sh.edges[e] = {"chain": chain, "smooth": anchors.map(func(_a): return true)}
	return sh


## Signed perpendicular offset (edge lengths) of the outline from edge e at t.
static func _ray_offset(sh: Dictionary, e: int, t: float, poly: PackedVector2Array) -> float:
	var a := Shape.corner(sh, e)
	var b := Shape.corner(sh, e + 1)
	var base := a.lerp(b, t)
	var dir := base.normalized()
	var best := base
	var bd := INF
	for i in poly.size():
		var hit = Geometry2D.segment_intersects_segment(Vector2.ZERO, dir * 10.0, poly[i], poly[(i + 1) % poly.size()])
		if hit != null and (hit as Vector2).length() < bd:
			bd = (hit as Vector2).length()
			best = hit
	var d := b - a
	return (best - base).dot(Vector2(-d.y, d.x)) / maxf(d.length_squared(), 1e-9)


## Artwork as SVG: each visible cell becomes a vector shape in its tile
## position with its colour, grouped by layer. Raster-only effects (CRT,
## fine textures, Display stack) are not included.
static func artwork_svg(project: ProjectData, frame: int, only_layer := -1) -> String:
	var px := project.canvas_px()
	var lines: Array[String] = ['<?xml version="1.0" encoding="UTF-8"?>',
		'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">' % [px.x, px.y, px.x, px.y]]
	for l in project.layers:
		if l.is_direction() or not l.visible or (only_layer >= 0 and l.id != only_layer):
			continue
		var t := project.tiling_for(l)
		var data := l.cells(frame)
		var style := int(l.setting("style"))
		lines.append('<g id="layer-%d" inkscape:label="%s" opacity="%.3f" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape">' % [l.id, l.name.xml_escape(), l.opacity])
		var inr := t.inradius()
		for i in data.size():
			var v := data[i]
			if v == 0 or v > project.palette.size():
				continue
			var c := t.cell_of_index(i)
			var col := project.palette[v - 1].to_html(false)
			if style == LayerData.Style.DOT or style == LayerData.Style.LED or style == LayerData.Style.LITE_BRITE:
				var ctr := t.cell_center(c)
				lines.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="#%s"/>' % [ctr.x, ctr.y, inr * float(l.setting("dot_size")), col])
			else:
				var pts := t.cell_polygon(c)
				var ps: Array[String] = []
				for p in pts:
					ps.append("%.2f,%.2f" % [p.x, p.y])
				lines.append('<polygon points="%s" fill="#%s"/>' % [" ".join(ps), col])
		lines.append("</g>")
	lines.append("</svg>")
	return "\n".join(lines)
