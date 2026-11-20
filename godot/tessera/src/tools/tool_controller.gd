class_name ToolController
extends RefCounted
## All drawing tools. Every tool talks to the active layer only through its
## Tiling (point_to_cell, cell_center, neighbors, cells_in_*), so tools work
## unchanged on every tiling. Shapes are computed in canvas space, then
## filled into whichever cells of the tiling they cover.

const TOOLS := {
	"pencil": {"name": "Pencil", "key": KEY_B},
	"eraser": {"name": "Eraser", "key": KEY_E},
	"eyedropper": {"name": "Eyedropper", "key": KEY_I},
	"line": {"name": "Line", "key": KEY_L},
	"rect": {"name": "Rectangle", "key": KEY_U},
	"ellipse": {"name": "Ellipse", "key": KEY_O},
	"fill": {"name": "Flood fill", "key": KEY_G},
	"select_rect": {"name": "Rectangle select", "key": KEY_M},
	"lasso": {"name": "Lasso select", "key": KEY_Q},
	"wand": {"name": "Magic wand", "key": KEY_W},
	"move": {"name": "Move", "key": KEY_V},
}
const ORDER := ["pencil", "eraser", "eyedropper", "line", "rect", "ellipse", "fill", "select_rect", "lasso", "wand", "move"]

var active := false
var erase := false
var start := Vector2.ZERO
var last := Vector2.ZERO
var current := Vector2.ZERO
var lasso := PackedVector2Array()
var _layer: LayerData
var _frame := 0
var _before := PackedByteArray()
var _tool := ""
var _mods := {}
var _lifted: Array = []  # [[center: Vector2, value: int], ...] for move
var _lift_ref := Vector2.ZERO
var _stroke := PackedVector2Array()  # direction layer stroke


# ---- helpers ---------------------------------------------------------------

func _t() -> Tiling:
	return App.tiling_of(_layer)


func _wrap_on() -> bool:
	return App.wrap_draw or App.tile_preview


func _wrap(p: Vector2) -> Vector2:
	if not _wrap_on():
		return p
	var px := App.project.canvas_px()
	return Vector2(fposmod(p.x, px.x), fposmod(p.y, px.y))


## Mirror transforms about the canvas center (identity first).
func _mirrors() -> Array[Transform2D]:
	var px := App.project.canvas_px()
	var out: Array[Transform2D] = [Transform2D.IDENTITY]
	var fx := Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(px.x, 0))
	var fy := Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(0, px.y))
	if App.mirror == 1 or App.mirror == 3:
		out.append(fx)
	if App.mirror == 2 or App.mirror == 3:
		out.append(fy)
	if App.mirror == 3:
		out.append(fx * fy)
	return out


func _value() -> int:
	return 0 if erase else App.color_index


func _can_edit() -> bool:
	return _layer != null and not _layer.locked and _layer.visible


func _set_cells(cells: Array, v: int, data: PackedByteArray) -> void:
	var t := _t()
	var sel := App.has_selection()
	for c in cells:
		if not t.in_grid(c):
			continue
		var i := t.index(c)
		if sel and (i >= App.selection.size() or App.selection[i] == 0):
			continue
		data[i] = v


## Apply a list of canvas-space cells plus every mirror image of them.
func _apply_mirrored(cells: Array, v: int, data: PackedByteArray) -> void:
	var t := _t()
	var mirrors := _mirrors()
	var all: Array = []
	for m in mirrors:
		if m == Transform2D.IDENTITY:
			all.append_array(cells)
		else:
			for c in cells:
				all.append(t.point_to_cell(_wrap(m * t.cell_center(c))))
	_set_cells(all, v, data)


func _brush_cells(p: Vector2) -> Array[Vector2i]:
	var t := _t()
	var size: int = App.tool_opts.brush
	var radius := (size - 1) * t.cs * 0.5 + 0.01
	if size <= 1:
		var single: Array[Vector2i] = []
		var c := t.point_to_cell(_wrap(p))
		if t.in_grid(c):
			single.append(c)
		return single
	if not _wrap_on():
		return t.cells_in_disc(p, radius)
	var out: Array[Vector2i] = []
	for off in _wrap_offsets():
		out.append_array(t.cells_in_disc(p + off, radius))
	return out


func _wrap_offsets() -> Array[Vector2]:
	var px := App.project.canvas_px()
	var out: Array[Vector2] = [Vector2.ZERO]
	if _wrap_on():
		for y in [-1, 0, 1]:
			for x in [-1, 0, 1]:
				if x != 0 or y != 0:
					out.append(Vector2(x * px.x, y * px.y))
	return out


func _segment_cells(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var t := _t()
	var out: Array[Vector2i] = []
	var seen := {}
	var brush: int = App.tool_opts.brush
	for p in t.sample_segment(a, b):
		if brush <= 1:
			var c := t.point_to_cell(_wrap(p))
			if t.in_grid(c) and not seen.has(c):
				seen[c] = true
				out.append(c)
		else:
			for c in _brush_cells(p):
				if not seen.has(c):
					seen[c] = true
					out.append(c)
	return out


func _emit() -> void:
	App.layer_cells_changed.emit(_layer.id)


# ---- event entry points ----------------------------------------------------

func press(p: Vector2, right_button: bool, mods: Dictionary) -> void:
	_layer = App.active_layer()
	if _layer == null:
		return
	_frame = App.frame
	_mods = mods
	erase = right_button
	_tool = App.tool
	if right_button and _tool in ["eyedropper", "fill", "line", "rect", "ellipse", "move", "select_rect", "lasso", "wand"]:
		_tool = "eraser"  # right button always erases
	if _tool == "pencil" and mods.get("alt", false):
		_tool = "eyedropper"
	active = true
	start = p
	last = p
	current = p
	if _layer.is_direction():
		_direction_press(p)
		return
	_t()  # normalises the layer's cell arrays to its tiling before snapshotting
	_before = _layer.cells(_frame).duplicate()
	match _tool:
		"pencil", "eraser":
			if _tool == "eraser":
				erase = true
			if not _can_edit():
				active = false
				App.status.emit("Layer is locked or hidden")
				return
			var data := _layer.cells(_frame)
			_apply_mirrored(_brush_cells(p), _value(), data)
			_emit()
		"eyedropper":
			_pick(p)
		"fill":
			if _can_edit():
				_fill(p)
			active = false
		"lasso":
			lasso = PackedVector2Array([p])
		"wand":
			_wand(p)
			active = false
		"move":
			if not _can_edit():
				active = false
				return
			_lift()
		"line", "rect", "ellipse":
			if not _can_edit():
				active = false
				App.status.emit("Layer is locked or hidden")


func drag(p: Vector2, mods: Dictionary) -> void:
	if not active or _layer == null:
		return
	_mods = mods
	current = p
	if _layer.is_direction():
		_direction_drag(p)
		return
	match _tool:
		"pencil", "eraser":
			var data := _layer.cells(_frame)
			_apply_mirrored(_segment_cells(last, p), _value(), data)
			last = p
			_emit()
		"eyedropper":
			_pick(p)
		"line", "rect", "ellipse":
			_preview_shape()
		"lasso":
			if lasso.is_empty() or lasso[lasso.size() - 1].distance_to(p) > 0.5:
				lasso.append(p)
		"move":
			_move_preview()
		"select_rect":
			pass


func release(p: Vector2, mods: Dictionary) -> void:
	if not active or _layer == null:
		active = false
		return
	_mods = mods
	current = p
	active = false
	if _layer.is_direction():
		_direction_release()
		return
	match _tool:
		"pencil", "eraser":
			App.commit_cells("Erase" if erase else "Draw", _layer, _frame, _before)
		"line", "rect", "ellipse":
			_preview_shape()
			App.commit_cells(ToolController.TOOLS[_tool].name, _layer, _frame, _before)
		"select_rect":
			var r := Rect2(start, Vector2.ZERO).expand(p)
			_combine_selection(_t().cells_in_rect(r))
		"lasso":
			lasso.append(p)
			_combine_selection(_t().cells_in_polygon(lasso))
			lasso = PackedVector2Array()
		"move":
			_move_preview()
			_finish_move()


func cancel() -> void:
	if active and _layer and _tool in ["pencil", "eraser", "line", "rect", "ellipse", "move"] and not _layer.is_direction():
		_layer.set_cells(_frame, _before.duplicate())
		_emit()
	active = false
	lasso = PackedVector2Array()


# ---- individual tools ------------------------------------------------------

func _pick(p: Vector2) -> void:
	var t := _t()
	var c := t.point_to_cell(_wrap(p))
	if t.in_grid(c):
		var v := _layer.cells(_frame)[t.index(c)]
		if v > 0:
			App.set_color(v)


func _constrained_end() -> Vector2:
	var d := current - start
	if _mods.get("shift", false):
		if _tool == "line":
			var step := deg_to_rad(_t().rotation_step_deg() * 0.5)
			var a := roundf(d.angle() / step) * step
			return start + Vector2.from_angle(a) * d.length()
		var m := maxf(absf(d.x), absf(d.y))
		return start + Vector2(signf(d.x) * m if d.x != 0 else m, signf(d.y) * m if d.y != 0 else m)
	return current


func shape_rect() -> Rect2:
	var e := _constrained_end()
	if _mods.get("ctrl", false):
		var half := e - start
		return Rect2(start - half.abs(), half.abs() * 2.0)
	return Rect2(start, Vector2.ZERO).expand(e)


func _preview_shape() -> void:
	var data := _before.duplicate()
	var t := _t()
	var cells: Array[Vector2i] = []
	var filled: bool = App.tool_opts.filled
	match _tool:
		"line":
			cells = _segment_cells(start, _constrained_end())
		"rect":
			var r := shape_rect()
			if filled:
				for off in _wrap_offsets():
					cells.append_array(t.cells_in_rect(Rect2(r.position + off, r.size)))
			else:
				var a := r.position
				var b := r.end
				for seg in [[a, Vector2(b.x, a.y)], [Vector2(b.x, a.y), b], [b, Vector2(a.x, b.y)], [Vector2(a.x, b.y), a]]:
					cells.append_array(_segment_cells(seg[0], seg[1]))
		"ellipse":
			var r := shape_rect()
			var ctr := r.get_center()
			var radii := r.size * 0.5
			if filled:
				for off in _wrap_offsets():
					cells.append_array(t.cells_in_ellipse(ctr + off, radii))
			else:
				var perim := TAU * sqrt((radii.x * radii.x + radii.y * radii.y) * 0.5)
				var n := maxi(12, int(perim / maxf(t.inradius(), 0.5)))
				var prev := ctr + Vector2(radii.x, 0)
				for i in range(1, n + 1):
					var a := TAU * i / n
					var q := ctr + Vector2(cos(a) * radii.x, sin(a) * radii.y)
					cells.append_array(_segment_cells(prev, q))
					prev = q
	_apply_mirrored(cells, _value(), data)
	_layer.set_cells(_frame, data)
	_emit()


func _match_table(target: int, tol: float) -> PackedByteArray:
	# Which cell values count as "the same colour" (OKLab distance on the
	# palette, so this is per palette entry, not per cell).
	var table := PackedByteArray()
	table.resize(256)
	var pal := App.project.palette
	for v in 256:
		if v == target:
			table[v] = 1
		elif tol > 0.0 and v > 0 and target > 0 and v <= pal.size() and target <= pal.size():
			table[v] = 1 if OkLab.distance(pal[v - 1], pal[target - 1]) <= tol else 0
	return table


func _region(seed: Vector2i, data: PackedByteArray, table: PackedByteArray, global: bool) -> PackedInt32Array:
	var t := _t()
	var out := PackedInt32Array()
	if global:
		for i in data.size():
			if table[data[i]] == 1:
				out.append(i)
		return out
	var seen := PackedByteArray()
	seen.resize(data.size())
	var stack: Array[Vector2i] = [seed]
	seen[t.index(seed)] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		out.append(t.index(c))
		for n in t.neighbors(c):
			var ni := t.index(n)
			if seen[ni] == 0 and table[data[ni]] == 1:
				seen[ni] = 1
				stack.append(n)
	return out


func _fill(p: Vector2) -> void:
	var t := _t()
	var data := _layer.cells(_frame)
	var global: bool = App.tool_opts.fill_global or _mods.get("shift", false)
	var tol: float = App.tool_opts.tolerance
	var v := _value()
	var sel := App.has_selection()
	for m in _mirrors():
		var c := t.point_to_cell(_wrap(m * p))
		if not t.in_grid(c):
			continue
		var target := data[t.index(c)]
		if target == v and tol <= 0.0:
			continue
		var region := _region(c, data, _match_table(target, tol), global)
		for i in region:
			if not sel or (i < App.selection.size() and App.selection[i] != 0):
				data[i] = v
	_emit()
	App.commit_cells("Fill", _layer, _frame, _before)


func _wand(p: Vector2) -> void:
	var t := _t()
	var c := t.point_to_cell(_wrap(p))
	if not t.in_grid(c):
		if not _mods.get("shift", false) and not _mods.get("ctrl", false):
			App.clear_selection()
		return
	var data := _layer.cells(_frame)
	var global: bool = App.tool_opts.wand_global or _mods.get("alt", false)
	var region := _region(c, data, _match_table(data[t.index(c)], App.tool_opts.wand_tolerance), global)
	var cells: Array[Vector2i] = []
	for i in region:
		cells.append(t.cell_of_index(i))
	_combine_selection(cells)


func _combine_selection(cells: Array[Vector2i]) -> void:
	var t := _t()
	var mask: PackedByteArray
	var add: bool = _mods.get("shift", false)
	var sub: bool = _mods.get("ctrl", false)
	if (add or sub) and App.has_selection():
		mask = App.selection.duplicate()
	else:
		mask = PackedByteArray()
	mask.resize(t.cell_count())
	for c in cells:
		if t.in_grid(c):
			mask[t.index(c)] = 0 if sub else 255
	App.set_selection(mask)


# ---- move ------------------------------------------------------------------

func _lift() -> void:
	var t := _t()
	_lifted.clear()
	var data := _before
	var sel := App.has_selection()
	var sum := Vector2.ZERO
	for i in data.size():
		if data[i] == 0:
			continue
		if sel and (i >= App.selection.size() or App.selection[i] == 0):
			continue
		var ctr := t.cell_center(t.cell_of_index(i))
		_lifted.append([ctr, data[i]])
		sum += ctr
	if _lifted.is_empty():
		active = false
		return
	_lift_ref = _lifted[0][0]


func _snapped_offset() -> Vector2:
	# Snap to a lattice translation so every lifted cell lands on a cell.
	var t := _t()
	var raw := current - start
	var target := t.point_to_cell(_lift_ref + raw)
	if target == Tiling.INVALID:
		return raw
	return t.cell_center(target) - _lift_ref


func _move_preview() -> void:
	var t := _t()
	var data := _before.duplicate()
	var copy: bool = _mods.get("alt", false)
	if not copy:
		for e in _lifted:
			var c := t.point_to_cell(e[0])
			if t.in_grid(c):
				data[t.index(c)] = 0
	var off := _snapped_offset()
	for e in _lifted:
		var c := t.point_to_cell(_wrap(e[0] + off))
		if t.in_grid(c):
			data[t.index(c)] = e[1]
	_layer.set_cells(_frame, data)
	_emit()


func _finish_move() -> void:
	var t := _t()
	if App.has_selection():
		var off := _snapped_offset()
		var mask := PackedByteArray()
		mask.resize(t.cell_count())
		for e in _lifted:
			var c := t.point_to_cell(_wrap(e[0] + off))
			if t.in_grid(c):
				mask[t.index(c)] = 255
		App.set_selection(mask)
	App.commit_cells("Move", _layer, _frame, _before)


# ---- direction layer ---------------------------------------------------------

func _direction_press(p: Vector2) -> void:
	if _layer.locked:
		active = false
		return
	if erase or _tool == "eraser":
		_erase_strokes_near(p)
		return
	_stroke = PackedVector2Array([p])


func _direction_drag(p: Vector2) -> void:
	if erase or _tool == "eraser":
		_erase_strokes_near(p)
		return
	if _stroke.size() > 0 and _stroke[_stroke.size() - 1].distance_to(p) >= App.project.cell_size * 0.5:
		_stroke.append(p)


func _direction_release() -> void:
	if erase or _tool == "eraser" or _stroke.size() < 2:
		_stroke = PackedVector2Array()
		return
	var s := _stroke
	_stroke = PackedVector2Array()
	var lid := _layer.id
	App.perform("Draw direction", func():
		App.project.layer_by_id(lid).strokes.append(s))


func _erase_strokes_near(p: Vector2) -> void:
	var radius := App.project.cell_size * 1.5
	for i in range(_layer.strokes.size() - 1, -1, -1):
		var s: PackedVector2Array = _layer.strokes[i]
		for j in range(s.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, s[j], s[j + 1]).distance_to(p) < radius:
				var lid := _layer.id
				var idx := i
				App.perform("Erase direction", func():
					App.project.layer_by_id(lid).strokes.remove_at(idx))
				return


func pending_stroke() -> PackedVector2Array:
	return _stroke
