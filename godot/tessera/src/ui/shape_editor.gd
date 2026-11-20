class_name ShapeEditor
extends Window
## One editor for all custom shapes: tiling shapes (always tile, paired
## edges) and stamp shapes (free paths with holes, used by the SVG stamp
## cell style). Shapes live in the project (embedded) and can be saved to
## the user library.

var canvas: ShapeCanvas
var _list: ItemList
var _ids: Array = []
var _name: LineEdit
var _info: Label
var _import_dialog: FileDialog
var _export_dialog: FileDialog
var _import_mode := 0
var _import_base := "square"
var _before_edit: Dictionary = {}


func _init() -> void:
	title = "Shape Editor"
	size = Vector2i(1100, 720)
	min_size = Vector2i(700, 480)
	close_requested.connect(hide)
	transient = false


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.13, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HSplitContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	root.add_child(UiKit.margin(left, 6))
	left.add_child(UiKit.header("Shapes in this project"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i): _select(_ids[i]))
	left.add_child(_list)
	var newt := UiKit.option(["+ Tiling shape from…"] + Shape.BUILTINS, 0, func(i):
		if i > 0:
			_add(Shape.builtin(Shape.BUILTINS[i - 1])))
	left.add_child(newt)
	left.add_child(UiKit.hbox([
		UiKit.button("+ Stamp", func(): _add(Shape.new_stamp())),
		UiKit.button("Duplicate", _duplicate),
		UiKit.button("Delete", _delete),
	]))
	left.add_child(HSeparator.new())
	left.add_child(UiKit.header("SVG"))
	left.add_child(UiKit.option(["Import as stamp shape", "Import fitted to a base tile (tiling)"], 0, func(i): _import_mode = i))
	left.add_child(UiKit.hbox([UiKit.label("Base"), UiKit.option(Shape.BASES, 0, func(i): _import_base = Shape.BASES[i])]))
	left.add_child(UiKit.hbox([
		UiKit.button("Import SVG…", func(): _import_dialog.popup_centered_ratio(0.6)),
		UiKit.button("Export SVG…", func(): _export_dialog.popup_centered_ratio(0.6)),
	]))
	left.add_child(HSeparator.new())
	left.add_child(UiKit.header("Use on the selected layer"))
	left.add_child(UiKit.button("As this layer's tiling", _use_as_tiling))
	left.add_child(UiKit.button("As this layer's SVG stamp", _use_as_stamp))
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var bar := HBoxContainer.new()
	_name = LineEdit.new()
	_name.placeholder_text = "Shape name"
	_name.custom_minimum_size.x = 200
	_name.text_submitted.connect(_rename)
	_name.focus_exited.connect(func(): _rename(_name.text))
	bar.add_child(_name)
	bar.add_child(UiKit.toggle("Snap to grid", false, func(on):
		canvas.snap = on
		canvas.queue_redraw()))
	bar.add_child(UiKit.button("Sharp / smooth (S)", func():
		_on_edit_started()
		canvas.toggle_smooth()
		_on_edit_finished()))
	bar.add_child(UiKit.button("+ Path / hole", _add_path, "Stamp shapes: add another closed path (inside another = hole)"))
	center.add_child(UiKit.margin(bar, 4))
	canvas = ShapeCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.edit_started.connect(_on_edit_started)
	canvas.edited.connect(func(): canvas.queue_redraw())
	canvas.edit_finished.connect(_on_edit_finished)
	center.add_child(canvas)
	_info = UiKit.label("", true)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(UiKit.margin(_info, 4))
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.svg ; SVG"])
	_import_dialog.file_selected.connect(_import)
	add_child(_import_dialog)
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.svg ; SVG"])
	_export_dialog.file_selected.connect(_export)
	add_child(_export_dialog)
	App.document_changed.connect(_refresh)
	_refresh()


func _current() -> Dictionary:
	return canvas.shape


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	_ids = App.project.shapes.keys()
	for id in _ids:
		var sh: Dictionary = App.project.shapes[id]
		_list.add_item(("▦ " if sh.kind == "tiling" else "✦ ") + sh.name)
	var cur: Dictionary = canvas.shape
	if not cur.is_empty() and App.project.shapes.has(cur.get("id", "")):
		canvas.set_shape(App.project.shapes[cur.id])
		_list.select(_ids.find(cur.id))
	elif not _ids.is_empty():
		_select(_ids[0])
	else:
		canvas.set_shape({})
	_update_info()


func _select(id: String) -> void:
	canvas.set_shape(App.project.shapes[id])
	_name.text = canvas.shape.name
	_update_info()


func _update_info() -> void:
	var sh := _current()
	if sh.is_empty():
		_info.text = "Create a tiling shape (always tiles) or a stamp shape."
		return
	if sh.kind == "tiling":
		_info.text = "Tiling shape (%s base). Drag corners and points; the paired opposite edge follows, so it always tiles. Double-click an edge to add a point, right-click a point to delete it, S toggles sharp/smooth, shift-click or drag a box to select several. Wheel zooms, middle-drag pans." % sh.base
	else:
		_info.text = "Stamp shape: drawn inside each tile by the SVG stamp cell style. Double-click a curve to add a point, right-click to delete, S toggles sharp/smooth. Paths inside other paths become holes."


func _add(sh: Dictionary) -> void:
	App.perform("Add shape", func():
		App.project.shapes[sh.id] = sh
		App.project.register_shapes())
	_select(sh.id)
	_refresh()


func _duplicate() -> void:
	var cur := _current()
	if cur.is_empty():
		return
	var d := Shape.duplicate_shape(cur)
	d.id = Shape.new_id()
	d.name += " copy"
	_add(d)


func _delete() -> void:
	var cur := _current()
	if cur.is_empty():
		return
	for l in App.project.layers:
		if l.tiling_id == "shape:" + str(cur.id) or str(l.setting("stamp_shape")) == str(cur.id):
			App.status.emit("Shape is used by layer '%s'" % l.name)
			return
	App.perform("Delete shape", func(): App.project.shapes.erase(cur.id))
	canvas.set_shape({})
	_refresh()


func _rename(t: String) -> void:
	var cur := _current()
	if cur.is_empty() or t.strip_edges() == "" or t == cur.name:
		return
	App.perform("Rename shape", func(): cur.name = t.strip_edges())
	_refresh()


func _add_path() -> void:
	var cur := _current()
	if cur.is_empty() or cur.kind != "stamp":
		return
	_on_edit_started()
	var r := 0.12
	cur.paths.append({"points": Svg._poly_path([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)], true).points, "closed": true})
	cur.paths.back().points = Array(cur.paths.back().points)
	_on_edit_finished()
	canvas.queue_redraw()


# ---- edits: one undo step per completed edit; layers resample if needed ---------

func _on_edit_started() -> void:
	if App.in_change():
		return
	App.begin_change(["all"])


func _on_edit_finished() -> void:
	var cur := _current()
	if not cur.is_empty() and cur.kind == "tiling":
		var tid := "shape:" + str(cur.id)
		var olds := {}
		for l in App.project.layers:
			if l.tiling_id == tid:
				olds[l.id] = App.tiling_of(l)  # built from the pre-edit geometry
		LayerData.shape_epoch += 1
		App.project.register_shapes()
		for l in App.project.layers:
			if olds.has(l.id):
				var new_t := App.tiling_of(l)
				App.resample_layer(l, olds[l.id], new_t)
	else:
		LayerData.shape_epoch += 1
	App.end_change("Edit shape")
	App.document_changed.emit()


# ---- SVG -------------------------------------------------------------------------

func _import(path: String) -> void:
	var parsed := Svg.parse_file(path)
	if parsed.paths.is_empty():
		App.status.emit("No geometry found in " + path.get_file())
		return
	var nm := path.get_file().get_basename()
	var sh := Svg.to_stamp(parsed, nm) if _import_mode == 0 else Svg.to_tiling(parsed, _import_base, nm)
	_add(sh)


func _export(path: String) -> void:
	var cur := _current()
	if cur.is_empty():
		return
	if path.get_extension() == "":
		path += ".svg"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(Svg.shape_svg(cur))
	App.status.emit("Exported " + path.get_file())


func _use_as_tiling() -> void:
	var cur := _current()
	var l := App.active_layer()
	if cur.is_empty() or cur.kind != "tiling" or l == null or l.is_direction():
		App.status.emit("Pick a tiling shape and a pixel layer")
		return
	App.change_layer_tiling(l, "shape:" + str(cur.id), {})


func _use_as_stamp() -> void:
	var cur := _current()
	var l := App.active_layer()
	if cur.is_empty() or cur.kind != "stamp" or l == null or l.is_direction():
		App.status.emit("Pick a stamp shape and a pixel layer")
		return
	App.perform("Use SVG stamp", func():
		l.settings.style = LayerData.Style.SVG_STAMP
		l.settings.stamp_shape = cur.id)
