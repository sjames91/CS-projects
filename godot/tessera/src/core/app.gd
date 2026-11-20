extends Node
## Central editor state (autoload "App"). Panels listen to its signals; every
## change that should be undoable goes through the helpers at the bottom.

signal document_changed            # anything structural: rebuild everything
signal layers_changed              # layer list / layer meta (name, visibility, order...)
signal layer_cells_changed(layer_id: int)
signal layer_settings_changed(layer_id: int)
signal palette_changed
signal active_layer_changed
signal frame_changed
signal tool_changed
signal color_changed
signal view_changed
signal selection_changed
signal status(msg: String)
signal title_changed

var project: ProjectData
var project_path := ""
var dirty := false:
	set(v):
		if dirty != v:
			dirty = v
			title_changed.emit()

var undo := UndoStack.new()
var active_layer_id := -1
var frame := 0
var color_index := 1  # 1-based palette entry; 0 = empty
var tool := "pencil"
var tool_opts := {
	"brush": 1, "filled": false, "fill_global": false, "tolerance": 0.0,
	"wand_global": false, "wand_tolerance": 0.0,
}
var mirror := 0  # 0 none, 1 horizontal, 2 vertical, 3 both
var wrap_draw := false
var tile_preview := false
var render_on := true
var grid_on := true
var preview_lock := false
var selection := PackedByteArray()  # mask over the active layer's grid
var selection_layer_id := -1
var clipboard := {}
var hover_canvas_point := Vector2(-1e9, -1e9)
var max_cache_px := 2048
## Advances on every playback step (even with one frame) so animated
## effects (interlace, noise, drift) move while playing.
var anim_tick := 0
## Pattern map view (editor only): layer id -> slot index shown as grayscale.
var pattern_view := {}
## Selected stroke (index in the active direction layer's current frame).
var dir_selected := -1
## Show the flow field overlay even when not editing a direction layer.
var show_field := false


func _ready() -> void:
	new_project(ProjectData.create_default())


func new_project(p: ProjectData, path := "") -> void:
	project = p
	project_path = path
	undo.clear()
	frame = 0
	active_layer_id = p.layers.back().id if not p.layers.is_empty() else -1
	color_index = 1 if p.palette.size() > 0 else 0
	clear_selection(false)
	dirty = false
	document_changed.emit()
	active_layer_changed.emit()
	palette_changed.emit()
	color_changed.emit()
	title_changed.emit()


# ---- accessors --------------------------------------------------------------

func active_layer() -> LayerData:
	return project.layer_by_id(active_layer_id)


func tiling_of(layer: LayerData) -> Tiling:
	return project.tiling_for(layer)


func active_tiling() -> Tiling:
	var l := active_layer()
	return tiling_of(l) if l else null


func set_active_layer(layer_id: int) -> void:
	if layer_id == active_layer_id:
		return
	active_layer_id = layer_id
	clear_selection(false)
	active_layer_changed.emit()


func set_frame(f: int) -> void:
	f = clampi(f, 0, project.frame_count - 1)
	if f != frame:
		frame = f
		frame_changed.emit()


func set_tool(t: String) -> void:
	tool = t
	tool_changed.emit()


func set_color(idx: int) -> void:
	color_index = clampi(idx, 0, project.palette.size())
	color_changed.emit()


func current_color() -> Color:
	if color_index <= 0 or color_index > project.palette.size():
		return Color(0, 0, 0, 0)
	return project.palette[color_index - 1]


func set_view(key: String, value: Variant) -> void:
	set(key, value)
	view_changed.emit()


func any_solo() -> bool:
	for l in project.layers:
		if l.solo:
			return true
	return false


func layer_shown(l: LayerData) -> bool:
	if any_solo():
		return l.solo
	return l.visible


# ---- selection -------------------------------------------------------------

func has_selection() -> bool:
	return not selection.is_empty() and selection_layer_id == active_layer_id


func clear_selection(emit := true) -> void:
	selection = PackedByteArray()
	selection_layer_id = -1
	if emit:
		selection_changed.emit()


func set_selection(mask: PackedByteArray) -> void:
	var any := false
	for i in mask.size():
		if mask[i] != 0:
			any = true
			break
	selection = mask if any else PackedByteArray()
	selection_layer_id = active_layer_id if any else -1
	selection_changed.emit()


# ---- undoable edits ----------------------------------------------------------

## Cell edit: call with the bytes captured before the edit; records one step.
func commit_cells(action_name: String, layer: LayerData, f: int, before: PackedByteArray) -> void:
	var after := layer.cells(f).duplicate()
	if after == before:
		return
	var lid := layer.id
	var fi := layer.frame_index(f)
	var apply := func(data: PackedByteArray):
		var l := project.layer_by_id(lid)
		if l:
			l.frames[fi] = data.duplicate()
			layer_cells_changed.emit(lid)
	undo.push(action_name, apply.bind(before.duplicate()), apply.bind(after))
	dirty = true


## Any structural / settings change. frames_for lists layer ids whose cells
## the action rewrites (or ["all"]).
func perform(action_name: String, fn: Callable, frames_for: Array = []) -> void:
	var before := project.capture_state(frames_for)
	var sel_before := [selection.duplicate(), selection_layer_id, active_layer_id]
	fn.call()
	var after := project.capture_state(frames_for)
	var sel_after := [selection.duplicate(), selection_layer_id, active_layer_id]
	var restore := func(state: Dictionary, sel: Array):
		project.restore_state(state)
		active_layer_id = sel[2] if project.layer_by_id(sel[2]) else (project.layers.back().id if not project.layers.is_empty() else -1)
		selection = sel[0].duplicate()
		selection_layer_id = sel[1]
		frame = clampi(frame, 0, project.frame_count - 1)
		_emit_all()
	undo.push(action_name, restore.bind(before, sel_before), restore.bind(after, sel_after))
	dirty = true
	_emit_all()


## Two-phase version of perform() for slider drags: begin on press, end on
## release; everything in between becomes a single undo step.
var _pending_state := {}


func begin_change(frames_for: Array = []) -> void:
	_pending_state = {"state": project.capture_state(frames_for), "frames_for": frames_for,
		"sel": [selection.duplicate(), selection_layer_id, active_layer_id]}


func end_change(action_name: String) -> void:
	if _pending_state.is_empty():
		return
	var before: Dictionary = _pending_state.state
	var sel_before: Array = _pending_state.sel
	var after := project.capture_state(_pending_state.frames_for)
	var sel_after := [selection.duplicate(), selection_layer_id, active_layer_id]
	_pending_state = {}
	var restore := func(state: Dictionary, sel: Array):
		project.restore_state(state)
		active_layer_id = sel[2] if project.layer_by_id(sel[2]) else project.layers.back().id
		selection = sel[0].duplicate()
		selection_layer_id = sel[1]
		_emit_all()
	undo.push(action_name, restore.bind(before, sel_before), restore.bind(after, sel_after))
	dirty = true
	# Heavy maps (patterns, reaction-diffusion, flow) recompute now that
	# the change is complete.
	if active_layer_id >= 0:
		layer_settings_changed.emit(active_layer_id)
	view_changed.emit()


func in_change() -> bool:
	return not _pending_state.is_empty()


func _emit_all() -> void:
	document_changed.emit()
	layers_changed.emit()
	palette_changed.emit()
	active_layer_changed.emit()
	selection_changed.emit()
	frame_changed.emit()


func do_undo() -> void:
	undo.undo()
	status.emit("Undo")


func do_redo() -> void:
	undo.redo()
	status.emit("Redo")


# ---- operations that rewrite cell grids --------------------------------------

## Resample every frame of a layer from one tiling setup to another (GPU).
func resample_layer(layer: LayerData, from_t: Tiling, to_t: Tiling, offset := Vector2.ZERO) -> void:
	var out: Array[PackedByteArray] = []
	for f in layer.frames:
		out.append(Gpu.resample_cells(f, from_t, to_t, offset))
	layer.frames = out


func _layer_tiling_with(layer: LayerData, tid: String, tparams: Dictionary, mode: int, cell_size: int, canvas: Vector2) -> Tiling:
	return LayerData.make_tiling(tid, tparams, mode, float(layer.setting("offset_amount")), cell_size, canvas)


## Offset on/off changes the grid size by one row/column. Cells keep their
## coordinates (the content moves with the grid), so this is a plain
## re-stride of each frame (native Image blit, no per-cell loop).
func set_layer_offset(layer: LayerData, mode: int) -> void:
	perform("Offset", func():
		var old_t := tiling_of(layer)
		layer.settings["offset_mode"] = mode
		var new_t := tiling_of(layer)
		if old_t.grid != new_t.grid:
			var out: Array[PackedByteArray] = []
			for f in layer.frames:
				var src := Image.create_from_data(old_t.grid.x, old_t.grid.y, false, Image.FORMAT_R8, f)
				var dst := Image.create(new_t.grid.x, new_t.grid.y, false, Image.FORMAT_R8)
				dst.blit_rect(src, Rect2i(Vector2i.ZERO, old_t.grid.min(new_t.grid)), Vector2i.ZERO)
				out.append(dst.get_data())
			layer.frames = out
		if selection_layer_id == layer.id:
			clear_selection(false)
	, [layer.id])


func change_layer_tiling(layer: LayerData, new_id: String, new_params: Dictionary) -> void:
	perform("Change tiling", func():
		var mode := int(layer.setting("offset_mode"))
		var old_t := _layer_tiling_with(layer, layer.tiling_id, layer.tiling_params, mode, project.cell_size, project.canvas_px())
		var new_t := _layer_tiling_with(layer, new_id, new_params, mode, project.cell_size, project.canvas_px())
		resample_layer(layer, old_t, new_t)
		layer.tiling_id = new_id
		layer.tiling_params = new_params.duplicate()
		if selection_layer_id == layer.id:
			clear_selection(false)
	, [layer.id])


## anchor: (0..1, 0..1), e.g. (0.5, 0.5) = center.
func resize_canvas(new_cells: Vector2i, new_cell_size: int, anchor: Vector2) -> void:
	perform("Resize canvas", func():
		var old_px := project.canvas_px()
		var new_px := Vector2(new_cells * new_cell_size)
		# Offset of the old canvas inside the new one (in new px), snapped to whole cells.
		var scale := float(new_cell_size) / float(project.cell_size)
		var delta := ((new_px - old_px * scale) * anchor / new_cell_size).round() * new_cell_size
		for l in project.layers:
			var mode := int(l.setting("offset_mode"))
			var old_t := _layer_tiling_with(l, l.tiling_id, l.tiling_params, mode, project.cell_size, old_px)
			var new_t := _layer_tiling_with(l, l.tiling_id, l.tiling_params, mode, new_cell_size, new_px)
			if scale == 1.0:
				resample_layer(l, old_t, new_t, -delta)
			else:
				# Cell size change: the old grid scaled up has the same cell
				# coordinates, so map from a scaled copy of the old tiling.
				var scaled_t := _layer_tiling_with(l, l.tiling_id, l.tiling_params, mode, new_cell_size, old_px * scale)
				resample_layer(l, scaled_t, new_t, -delta)
			for fr in l.stroke_frames:
				for st in fr:
					var pts := PackedVector2Array()
					for v in st.points:
						pts.append(v * scale + delta)
					st.points = pts
					st.radius = float(st.radius) * scale
		project.canvas_cells = new_cells
		project.cell_size = new_cell_size
		clear_selection(false)
	, ["all"])


func set_frame_count_internal(n: int) -> void:
	project.frame_count = n
	project.frame_durations.resize(n)


## Palette edit that keeps every cell on its colour. `table[old] = new`.
func remap_all_cells(table: PackedByteArray) -> void:
	for l in project.layers:
		for i in l.frames.size():
			l.frames[i] = Gpu.remap_cells(l.frames[i], table)


func palette_remove(idx: int) -> void:  # idx is 1-based
	if idx < 1 or idx > project.palette.size():
		return
	perform("Remove colour", func():
		var table := PackedByteArray()
		table.resize(256)
		for v in 256:
			table[v] = 0 if v == idx else (v - 1 if v > idx else v)
		remap_all_cells(table)
		project.palette.remove_at(idx - 1)
		color_index = clampi(color_index, 0, project.palette.size())
	, ["all"])


func palette_move(idx: int, to: int) -> void:  # 1-based
	var n := project.palette.size()
	if idx < 1 or idx > n or to < 1 or to > n or idx == to:
		return
	perform("Reorder palette", func():
		var order := range(1, n + 1)
		order.remove_at(idx - 1)
		order.insert(to - 1, idx)
		var table := PackedByteArray()
		table.resize(256)
		for v in 256:
			table[v] = v
		var newpal := PackedColorArray()
		for new_i in order.size():
			table[order[new_i]] = new_i + 1
			newpal.append(project.palette[order[new_i] - 1])
		remap_all_cells(table)
		project.palette = newpal
		color_index = table[color_index] if color_index > 0 else 0
	, ["all"])


func palette_set(new_palette: PackedColorArray, keep_cells_by_color: bool) -> void:
	perform("Set palette", func():
		if keep_cells_by_color and new_palette.size() > 0:
			# Map every old entry to the nearest new entry (OKLab).
			var table := PackedByteArray()
			table.resize(256)
			for v in range(1, mini(project.palette.size(), 255) + 1):
				var best := 1
				var bd := INF
				for j in new_palette.size():
					var d := OkLab.distance(project.palette[v - 1], new_palette[j])
					if d < bd:
						bd = d
						best = j + 1
				table[v] = best
			remap_all_cells(table)
		project.palette = new_palette.slice(0, 255)
		color_index = clampi(color_index, 1 if project.palette.size() > 0 else 0, project.palette.size())
	, ["all"])
