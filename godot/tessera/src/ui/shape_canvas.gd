class_name ShapeCanvas
extends Control
## Editing surface of the Shape Editor. Tiling shapes are edited through
## their stored half (corners 0..k/2-1, edges 0..k/2-1); anything grabbed
## on a derived corner or paired edge is mapped back, so opposite edges stay
## exact copies and the shape always tiles. Same mouse controls as the main
## canvas: wheel zoom at cursor, middle-drag pan.

signal edit_started
signal edited
signal edit_finished

var shape: Dictionary = {}
var zoom := 220.0
var pan := Vector2.ZERO
var snap := false
var selected: Array = []  # pickable keys
var _drag := {}
var _panning := false
var _pan_from := Vector2.ZERO
var _box_from := Vector2.INF
var _hover_key := ""


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	resized.connect(func(): queue_redraw())


func set_shape(s: Dictionary) -> void:
	shape = s
	selected.clear()
	queue_redraw()


func to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + pan + p * zoom


func to_shape(s: Vector2) -> Vector2:
	return (s - size * 0.5 - pan) / zoom


func _snap(p: Vector2) -> Vector2:
	return (p * 16.0).round() / 16.0 if snap else p


# ---- pickables -----------------------------------------------------------------
# key formats: "c:i" corner, "e:edge:j" point j of an edge chain (1..L, no
# corners), "s:path:j" stamp path point j.

func _pickables() -> Array:
	var out: Array = []
	if shape.is_empty():
		return out
	if shape.kind == "tiling":
		for i in Shape.corner_count(shape):
			out.append({"key": "c:%d" % i, "pos": Shape.corner(shape, i), "type": "corner"})
		for e in Shape.corner_count(shape):
			var ch := Shape.edge_chain(shape, e)
			for j in range(1, ch.size() - 1):
				var t := "anchor" if (j - 1) % 3 == 1 else "handle"
				out.append({"key": "e:%d:%d" % [e, j], "pos": ch[j], "type": t, "edge": e, "j": j})
	else:
		for pi in shape.paths.size():
			var pts: Array = shape.paths[pi].points
			for j in pts.size():
				out.append({"key": "s:%d:%d" % [pi, j], "pos": pts[j], "type": "anchor" if j % 3 == 0 else "handle", "path": pi, "j": j})
	return out


func _pick(screen: Vector2) -> Dictionary:
	var best := {}
	var bd := 9.0
	for p in _pickables():
		var d := to_screen(p.pos).distance_to(screen)
		var bias := 0.0 if p.type != "handle" else 1.5
		if d + bias < bd:
			bd = d + bias
			best = p
	return best


## The stored element a pickable edits: [base_edge, chain_index] (chain
## index excludes corners) for edge points.
func _base_of(edge: int, j: int) -> Array:
	var h: int = shape.corners.size()
	var L: int = (shape.edges[posmod(edge, h)].chain as Array).size()
	if edge < h:
		return [edge, j - 1]
	return [edge - h, L - j]


## Partner key (same stored element on the opposite edge / corner).
func partner_key(key: String) -> String:
	if shape.is_empty() or shape.kind != "tiling":
		return ""
	var parts := key.split(":")
	var h: int = shape.corners.size()
	if parts[0] == "c":
		return "c:%d" % posmod(int(parts[1]) + h, h * 2)
	if parts[0] == "e":
		var e := int(parts[1])
		var j := int(parts[2])
		var L: int = (shape.edges[posmod(e, h)].chain as Array).size()
		return "e:%d:%d" % [posmod(e + h, h * 2), L + 1 - j]
	return ""


func _get_pos(key: String) -> Vector2:
	for p in _pickables():
		if p.key == key:
			return p.pos
	return Vector2.ZERO


## Move a pickable to an absolute position (mapped onto the stored half).
func _set_pos(key: String, pos: Vector2, move_handles := true) -> void:
	var parts := key.split(":")
	if parts[0] == "c":
		var i := int(parts[1])
		var h: int = shape.corners.size()
		if i < h:
			shape.corners[i] = pos
		else:
			shape.corners[i - h] = -pos
	elif parts[0] == "e":
		var e := int(parts[1])
		var j := int(parts[2])
		var b := _base_of(e, j)
		var base: int = b[0]
		var idx: int = b[1]
		var h: int = shape.corners.size()
		var p_base := pos if e < h else pos - Shape.translation(shape, base)
		var chain: Array = shape.edges[base].chain
		var new_local := Shape.edge_local(shape, base, p_base)
		var delta: Vector2 = new_local - chain[idx]
		chain[idx] = new_local
		# Chain layout: [out(C), in(A0), A0, out(A0), in(A1), A1, ...]: anchors at 3k+2.
		var is_anchor := idx % 3 == 2 and idx < chain.size() - 1
		if is_anchor and move_handles:
			chain[idx - 1] += delta
			chain[idx + 1] += delta
		elif not is_anchor:
			_mirror_handle(chain, idx, (shape.edges[base].smooth as Array))
	elif parts[0] == "s":
		var pi := int(parts[1])
		var j2 := int(parts[2])
		var pts: Array = shape.paths[pi].points
		var d: Vector2 = pos - pts[j2]
		pts[j2] = pos
		if j2 % 3 == 0 and move_handles:
			for hj in [j2 - 1, j2 + 1]:
				if hj >= 0 and hj < pts.size():
					pts[hj] += d
			if shape.paths[pi].get("closed", true) and pts.size() > 1 and (j2 == 0 or j2 == pts.size() - 1):
				var other := pts.size() - 1 if j2 == 0 else 0
				pts[other] = pos
				var oh := other - 1 if other > 0 else other + 1
				if oh >= 0 and oh < pts.size():
					pts[oh] += d


## Smooth anchors keep their two handles collinear.
func _mirror_handle(chain: Array, idx: int, smooth: Array) -> void:
	# handle before an anchor sits at 3k+1, after at 3k+3 (k-th anchor at 3k+2)
	var anchor_idx := -1
	if idx % 3 == 1:
		anchor_idx = idx + 1
	elif idx % 3 == 0 and idx > 0:
		anchor_idx = idx - 1
	if anchor_idx <= 0 or anchor_idx >= chain.size() - 1:
		return
	var a := (anchor_idx - 2) / 3
	if a < 0 or a >= smooth.size() or not smooth[a]:
		return
	var other := anchor_idx * 2 - idx
	var dir: Vector2 = (chain[anchor_idx] - chain[idx]).normalized()
	var length: float = (chain[other] - chain[anchor_idx]).length()
	chain[other] = chain[anchor_idx] + dir * length


# ---- input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_pan_from = mb.position
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var p := _pick(mb.position)
			if not p.is_empty() and p.type == "anchor":
				edit_started.emit()
				_delete_anchor(p.key)
				edited.emit()
				edit_finished.emit()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			if mb.pressed and mb.double_click:
				_add_point_at(to_shape(mb.position))
				return
			if mb.pressed:
				var p := _pick(mb.position)
				if p.is_empty():
					if not mb.shift_pressed:
						selected.clear()
					_box_from = mb.position
				else:
					if mb.shift_pressed:
						if selected.has(p.key):
							selected.erase(p.key)
						else:
							selected.append(p.key)
					elif not selected.has(p.key):
						selected = [p.key]
					var starts := {}
					for k in selected:
						starts[k] = _get_pos(k)
					_drag = {"from": to_shape(mb.position), "starts": starts}
					edit_started.emit()
			else:
				if not _drag.is_empty():
					_drag = {}
					edit_finished.emit()
				if _box_from != Vector2.INF:
					var r := Rect2(_box_from, Vector2.ZERO).expand(mb.position)
					for p in _pickables():
						if r.has_point(to_screen(p.pos)) and not selected.has(p.key):
							selected.append(p.key)
					_box_from = Vector2.INF
		queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			pan += mm.position - _pan_from
			_pan_from = mm.position
		elif not _drag.is_empty():
			var d := to_shape(mm.position) - (_drag.from as Vector2)
			var only_one: bool = selected.size() == 1
			for k in selected:
				_set_pos(k, _snap(_drag.starts[k] + d), only_one)
			edited.emit()
		else:
			var p := _pick(mm.position)
			_hover_key = p.get("key", "")
		queue_redraw()
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
			edit_started.emit()
			for key in selected.duplicate():
				_delete_anchor(key)
			selected.clear()
			edited.emit()
			edit_finished.emit()
		elif k.keycode == KEY_S:
			edit_started.emit()
			toggle_smooth()
			edited.emit()
			edit_finished.emit()


func _zoom_at(pos: Vector2, f: float) -> void:
	var before := to_shape(pos)
	zoom = clampf(zoom * f, 20.0, 4000.0)
	pan += pos - to_screen(before)
	queue_redraw()


func _add_point_at(p: Vector2) -> void:
	edit_started.emit()
	if shape.kind == "tiling":
		var best_e := 0
		var bd := INF
		for e in Shape.corner_count(shape):
			var poly := Shape.flatten_chain(Shape.edge_chain(shape, e), 12)
			poly.append(Shape.edge_chain(shape, e)[-1])
			for i in range(poly.size() - 1):
				var d := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1]).distance_to(p)
				if d < bd:
					bd = d
					best_e = e
		Shape.add_edge_point(shape, best_e, p)
	else:
		_split_stamp_at(p)
	edited.emit()
	edit_finished.emit()


## Split the nearest stamp segment at the closest parameter.
func _split_stamp_at(p: Vector2) -> void:
	var best := [-1, -1, 0.0]
	var bd := INF
	for pi in shape.paths.size():
		var pts: Array = shape.paths[pi].points
		var i := 0
		while i + 3 < pts.size():
			for k in 33:
				var t := k / 32.0
				var q: Vector2 = (pts[i] as Vector2).bezier_interpolate(pts[i + 1], pts[i + 2], pts[i + 3], t)
				if q.distance_to(p) < bd:
					bd = q.distance_to(p)
					best = [pi, i, t]
			i += 3
	if best[0] < 0:
		return
	var pts2: Array = shape.paths[best[0]].points
	var i0: int = best[1]
	var t2: float = best[2]
	var a: Vector2 = pts2[i0]
	var b: Vector2 = pts2[i0 + 1]
	var c: Vector2 = pts2[i0 + 2]
	var d2: Vector2 = pts2[i0 + 3]
	var ab := a.lerp(b, t2)
	var bc := b.lerp(c, t2)
	var cd := c.lerp(d2, t2)
	var abc := ab.lerp(bc, t2)
	var bcd := bc.lerp(cd, t2)
	var m := abc.lerp(bcd, t2)
	pts2[i0 + 1] = ab
	pts2[i0 + 2] = cd
	pts2.insert(i0 + 2, bcd)
	pts2.insert(i0 + 2, m)
	pts2.insert(i0 + 2, abc)


func _delete_anchor(key: String) -> void:
	var parts := key.split(":")
	if parts[0] == "e":
		var b := _base_of(int(parts[1]), int(parts[2]))
		var idx: int = b[1]
		if idx % 3 == 2:
			Shape.remove_edge_anchor(shape, b[0], (idx - 2) / 3)
	elif parts[0] == "s":
		var pi := int(parts[1])
		var j := int(parts[2])
		var pts: Array = shape.paths[pi].points
		if j % 3 == 0 and pts.size() > 7 and j > 0 and j < pts.size() - 1:
			pts.remove_at(j + 1)
			pts.remove_at(j)
			pts.remove_at(j - 1)


## Convert the selected anchors between sharp and smooth.
func toggle_smooth() -> void:
	for key in selected:
		var parts: PackedStringArray = key.split(":")
		if parts[0] == "e":
			var b := _base_of(int(parts[1]), int(parts[2]))
			var idx: int = b[1]
			var e: Dictionary = shape.edges[b[0]]
			var a := (idx - 2) / 3
			if idx % 3 == 2 and a < e.smooth.size():
				e.smooth[a] = not e.smooth[a]
				if e.smooth[a]:
					var ch: Array = e.chain
					var tan: Vector2 = (ch[idx + 1] - ch[idx - 1]) * 0.5
					ch[idx - 1] = ch[idx] - tan
					ch[idx + 1] = ch[idx] + tan
		elif parts[0] == "s":
			var pts: Array = shape.paths[int(parts[1])].points
			var j := int(parts[2])
			if j % 3 == 0 and j > 0 and j < pts.size() - 1:
				var tan2: Vector2 = (pts[j + 1] - pts[j - 1]) * 0.5
				if tan2.length() < 1e-4:
					tan2 = Vector2(0.08, 0)
				pts[j - 1] = pts[j] - tan2
				pts[j + 1] = pts[j] + tan2


# ---- drawing --------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12))
	if shape.is_empty():
		return
	if snap:
		var g := 1.0 / 16.0 * zoom
		if g > 6:
			var o := to_screen(Vector2.ZERO)
			var x := fposmod(o.x, g)
			while x < size.x:
				draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.04))
				x += g
			var y := fposmod(o.y, g)
			while y < size.y:
				draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.04))
				y += g
	if shape.kind == "tiling":
		_draw_tiling()
	else:
		_draw_stamp()
	var hk := partner_key(_hover_key) if _drag.is_empty() else ""
	for p in _pickables():
		var sp := to_screen(p.pos)
		var sel := selected.has(p.key)
		var partner := false
		for k in selected:
			if partner_key(k) == p.key:
				partner = true
		if p.key == hk:
			partner = true
		var col := Color(1.0, 0.6, 0.2) if sel else (Color(0.3, 1.0, 0.8) if partner else Color.WHITE)
		match p.type:
			"corner":
				draw_rect(Rect2(sp - Vector2(5, 5), Vector2(10, 10)), col)
			"anchor":
				draw_circle(sp, 5.0, col)
			"handle":
				draw_circle(sp, 3.0, Color(col, 0.8))
	if _box_from != Vector2.INF:
		draw_rect(Rect2(_box_from, Vector2.ZERO).expand(get_local_mouse_position()), Color(1, 1, 1, 0.6), false, 1.0)


func _draw_tiling() -> void:
	var poly := Shape.polygon(shape, 16)
	var b := Shape.basis(shape)
	var u: Vector2 = b[0]
	var v: Vector2 = b[1]
	# Live preview: the shape tiled across a grid.
	for j in range(-3, 4):
		for i in range(-3, 4):
			var off := u * i + v * j
			var sp := PackedVector2Array()
			for p in poly:
				sp.append(to_screen(p + off))
			var shade := 0.18 + 0.06 * float(posmod(i + 2 * j, 3))
			if i == 0 and j == 0:
				draw_colored_polygon(sp, Color(0.32, 0.45, 0.7))
			else:
				draw_colored_polygon(sp, Color(shade, shade, shade + 0.03))
			sp.append(sp[0])
			draw_polyline(sp, Color(0, 0, 0, 0.5), 1.0)
	# Edges: stored half bright, paired half dim; handle lines.
	var h: int = shape.corners.size()
	for e in Shape.corner_count(shape):
		var ch := Shape.edge_chain(shape, e)
		var line := Shape.flatten_chain(ch, 16)
		line.append(ch[ch.size() - 1])
		var sl := PackedVector2Array()
		for p in line:
			sl.append(to_screen(p))
		draw_polyline(sl, Color(1, 0.85, 0.3) if e < h else Color(1, 0.85, 0.3, 0.45), 2.0)
		for j in range(0, ch.size() - 1, 3):
			draw_line(to_screen(ch[j]), to_screen(ch[j + 1]), Color(0.6, 0.9, 1.0, 0.35), 1.0)
			draw_line(to_screen(ch[j + 3]), to_screen(ch[j + 2]), Color(0.6, 0.9, 1.0, 0.35), 1.0)


func _draw_stamp() -> void:
	var box := Rect2(to_screen(Vector2(-0.5, -0.5)), Vector2.ONE * zoom)
	draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)
	for pa in shape.paths:
		var pts := PackedVector2Array(pa.points)
		var line := Shape.flatten_chain(pts, 16)
		if pts.size() > 0:
			line.append(pts[pts.size() - 1])
		var sl := PackedVector2Array()
		for p in line:
			sl.append(to_screen(p))
		if sl.size() > 2:
			draw_colored_polygon(sl, Color(0.32, 0.45, 0.7, 0.55))
		draw_polyline(sl, Color(1, 0.85, 0.3), 2.0)
		for j in range(0, pts.size() - 1, 3):
			if j + 3 < pts.size():
				draw_line(to_screen(pts[j]), to_screen(pts[j + 1]), Color(0.6, 0.9, 1.0, 0.35), 1.0)
				draw_line(to_screen(pts[j + 3]), to_screen(pts[j + 2]), Color(0.6, 0.9, 1.0, 0.35), 1.0)
