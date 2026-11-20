class_name SelectionOps
extends RefCounted
## Copy / cut / paste / delete / flip / rotate for the active layer.
## Content is carried as canvas-space cell centers, so it can be pasted into
## a layer with a different tiling, and rotation uses the tiling's own
## symmetry step and pivot snapping.


static func _targets(layer: LayerData) -> PackedInt32Array:
	var data := layer.cells(App.frame)
	var out := PackedInt32Array()
	var sel := App.has_selection()
	for i in data.size():
		if sel:
			if i < App.selection.size() and App.selection[i] != 0:
				out.append(i)
		elif data[i] != 0:
			out.append(i)
	return out


static func select_all() -> void:
	var t := App.active_tiling()
	if t == null:
		return
	var mask := PackedByteArray()
	mask.resize(t.cell_count())
	mask.fill(255)
	App.set_selection(mask)


static func copy() -> bool:
	var layer := App.active_layer()
	if layer == null or layer.is_direction():
		return false
	var t := App.tiling_of(layer)
	var data := layer.cells(App.frame)
	var items: Array = []
	for i in _targets(layer):
		if data[i] != 0:
			items.append([t.cell_center(t.cell_of_index(i)), data[i]])
	if items.is_empty():
		return false
	App.clipboard = {"items": items}
	App.status.emit("Copied %d cells" % items.size())
	return true


static func delete_selected(action_name := "Delete") -> void:
	var layer := App.active_layer()
	if layer == null or layer.locked or not App.has_selection():
		return
	var before := layer.cells(App.frame).duplicate()
	var data := layer.cells(App.frame)
	for i in _targets(layer):
		data[i] = 0
	App.layer_cells_changed.emit(layer.id)
	App.commit_cells(action_name, layer, App.frame, before)


static func cut() -> void:
	if copy():
		delete_selected("Cut")


## Paste at the same canvas position (or shifted so its center lands at `at`).
static func paste(at := Vector2(INF, INF)) -> void:
	var layer := App.active_layer()
	if layer == null or layer.locked or layer.is_direction() or App.clipboard.is_empty():
		return
	var t := App.tiling_of(layer)
	var items: Array = App.clipboard.items
	var off := Vector2.ZERO
	if at.x != INF:
		var sum := Vector2.ZERO
		for e in items:
			sum += e[0]
		var ref: Vector2 = items[0][0]
		var raw: Vector2 = at - sum / items.size()
		var target := t.point_to_cell(ref + raw)
		off = t.cell_center(target) - ref if target != Tiling.INVALID else raw
	var before := layer.cells(App.frame).duplicate()
	var data := layer.cells(App.frame)
	var mask := PackedByteArray()
	mask.resize(t.cell_count())
	for e in items:
		var c := t.point_to_cell(e[0] + off)
		if t.in_grid(c):
			data[t.index(c)] = e[1]
			mask[t.index(c)] = 255
	App.layer_cells_changed.emit(layer.id)
	App.commit_cells("Paste", layer, App.frame, before)
	App.set_selection(mask)


## Generic transform of the selected cells (or the whole layer) about a pivot
## snapped by the tiling, so cells map onto cells.
static func transform(kind: String) -> void:
	var layer := App.active_layer()
	if layer == null or layer.locked or layer.is_direction():
		return
	var t := App.tiling_of(layer)
	var idx := _targets(layer)
	if idx.is_empty():
		return
	var data := layer.cells(App.frame)
	var sum := Vector2.ZERO
	for i in idx:
		sum += t.cell_center(t.cell_of_index(i))
	var pivot := t.snap_pivot(sum / idx.size())
	var xf: Transform2D
	match kind:
		"flip_h":
			if not t.can_flip_h():
				return
			xf = Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(2.0 * pivot.x, 0))
		"flip_v":
			if not t.can_flip_v():
				return
			xf = Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(0, 2.0 * pivot.y))
		"rot_cw", "rot_ccw":
			var a := deg_to_rad(t.rotation_step_deg()) * (1.0 if kind == "rot_cw" else -1.0)
			xf = Transform2D(0.0, pivot) * Transform2D(a, Vector2.ZERO) * Transform2D(0.0, -pivot)
	var before := data.duplicate()
	var moved: Array = []
	for i in idx:
		moved.append([t.transform_cell(t.cell_of_index(i), xf), before[i]])
		data[i] = 0
	var sel := App.has_selection()
	var mask := PackedByteArray()
	mask.resize(t.cell_count())
	for m in moved:
		if t.in_grid(m[0]):
			var j := t.index(m[0])
			if m[1] != 0 or sel:
				data[j] = m[1]
			mask[j] = 255
	App.layer_cells_changed.emit(layer.id)
	App.commit_cells({"flip_h": "Flip horizontal", "flip_v": "Flip vertical", "rot_cw": "Rotate", "rot_ccw": "Rotate"}[kind], layer, App.frame, before)
	if sel:
		App.set_selection(mask)
