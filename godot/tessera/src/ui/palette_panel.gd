class_name PalettePanel
extends VBoxContainer
## Shared project palette. Order matters (ramps), so reordering remaps cells
## instead of recolouring them.

var _grid: HFlowContainer
var _picker: ColorPickerButton
var _pending := false
var _import_dialog: FileDialog
var _export_dialog: FileDialog
var _import_win: AcceptDialog
var _imp_image: Image
var _imp_mode := 0
var _imp_n := 16
var _imp_append := false
var _imp_preview: HFlowContainer
var _imp_colors := PackedColorArray()
var _imp_info: Label
var _drag_from := -1


func _ready() -> void:
	name = "Palette"
	var bar := HBoxContainer.new()
	_picker = UiKit.color_button(App.current_color(), _on_pick)
	_picker.tooltip_text = "Edit the current color"
	bar.add_child(_picker)
	bar.add_child(UiKit.button("+", _add, "Add a color (copy of the current one)"))
	bar.add_child(UiKit.button("−", func(): App.palette_remove(App.color_index), "Remove current color (cells using it become empty)"))
	bar.add_child(UiKit.button("◀", func(): App.palette_move(App.color_index, App.color_index - 1), "Move color earlier in the ramp"))
	bar.add_child(UiKit.button("▶", func(): App.palette_move(App.color_index, App.color_index + 1), "Move color later in the ramp"))
	bar.add_child(UiKit.button("Import PNG…", func(): _import_dialog.popup_centered_ratio(0.6), "Extract a palette from any PNG"))
	var exp := MenuButton.new()
	exp.text = "Export"
	exp.flat = false
	exp.get_popup().add_item("PNG swatch strip…", 0)
	exp.get_popup().add_item(".hex text…", 1)
	exp.get_popup().add_item(".gpl (GIMP) palette…", 2)
	exp.get_popup().id_pressed.connect(_export)
	bar.add_child(exp)
	add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(_grid)
	add_child(scroll)
	_build_dialogs()
	App.palette_changed.connect(_queue)
	App.document_changed.connect(_queue)
	App.color_changed.connect(_queue)
	_queue()


func _queue() -> void:
	if not _pending:
		_pending = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_pending = false
	for c in _grid.get_children():
		c.queue_free()
	var pal := App.project.palette
	for i in pal.size():
		_grid.add_child(_swatch(i + 1, pal[i]))
	_picker.color = App.current_color()


func _swatch(idx: int, c: Color) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(22, 22)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "#%d  %s  (L %.2f)\nClick: select · Drag: reorder" % [idx, c.to_html(false), OkLab.lightness(c)]
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_border_width_all(2 if idx == App.color_index else 0)
	sb.border_color = Color.WHITE
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag_from = idx
				App.set_color(idx)
			else:
				var target := _swatch_at(get_global_mouse_position())
				if _drag_from > 0 and target > 0 and target != _drag_from:
					App.palette_move(_drag_from, target)
				_drag_from = -1)
	return b


func _swatch_at(gp: Vector2) -> int:
	var i := 1
	for c in _grid.get_children():
		if (c as Control).get_global_rect().has_point(gp):
			return i
		i += 1
	return -1


func _on_pick(c: Color) -> void:
	var idx := App.color_index
	if idx < 1:
		return
	App.perform("Edit color", func(): App.project.palette[idx - 1] = c)


func _add() -> void:
	if App.project.palette.size() >= 255:
		App.status.emit("Palette is full (255 colors)")
		return
	var c := App.current_color() if App.color_index > 0 else Color.WHITE
	App.perform("Add color", func():
		var at := App.color_index
		App.project.palette.insert(at, c)
		# Cells referencing later entries keep their colour.
		var table := PackedByteArray()
		table.resize(256)
		for v in 256:
			table[v] = v + 1 if v > at and v < 255 else v
		App.remap_all_cells(table)
		App.color_index = at + 1
	, ["all"])


# ---- import ------------------------------------------------------------------

func _build_dialogs() -> void:
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.png ; PNG images"])
	_import_dialog.file_selected.connect(_on_import_file)
	add_child(_import_dialog)
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.file_selected.connect(_on_export_file)
	add_child(_export_dialog)
	_import_win = AcceptDialog.new()
	_import_win.title = "Import palette from PNG"
	_import_win.ok_button_text = "Apply"
	_import_win.min_size = Vector2i(520, 360)
	_import_win.confirmed.connect(_apply_import)
	var v := VBoxContainer.new()
	var mode := UiKit.option(["A · Exact unique colors (in image order)", "B · Reduce to N colors (k-means in OKLab)"], 0, func(i):
		_imp_mode = i
		_compute_import())
	v.add_child(mode)
	v.add_child(UiKit.slider_row("Colors (B)", 2, 64, 1, _imp_n, func(n): _imp_n = int(n), func(): pass, func(): _compute_import()))
	v.add_child(UiKit.option(["Replace palette (cells move to nearest new color)", "Append to palette"], 0, func(i): _imp_append = i == 1))
	_imp_info = UiKit.label("", true)
	v.add_child(_imp_info)
	_imp_preview = HFlowContainer.new()
	_imp_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_imp_preview)
	_import_win.add_child(v)
	add_child(_import_win)


func _on_import_file(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		App.status.emit("Could not load " + path)
		return
	_imp_image = img
	_compute_import()
	_import_win.popup_centered()


func _compute_import() -> void:
	if _imp_image == null:
		return
	if _imp_mode == 0:
		var r: Dictionary = Gpu.unique_colors(_imp_image, 255)
		_imp_colors = r.colors
		_imp_info.text = "%d unique colors%s" % [_imp_colors.size(), " — more than 255 found; try option B" if r.overflow else ""]
	else:
		_imp_colors = Gpu.reduce_colors(_imp_image, _imp_n)
		_imp_info.text = "%d colors, sorted into ramps by hue and lightness" % _imp_colors.size()
	for c in _imp_preview.get_children():
		c.queue_free()
	for c in _imp_colors:
		var r := ColorRect.new()
		r.color = c
		r.custom_minimum_size = Vector2(20, 20)
		_imp_preview.add_child(r)


func _apply_import() -> void:
	if _imp_colors.is_empty():
		return
	if _imp_append:
		var p := App.project.palette.duplicate()
		p.append_array(_imp_colors)
		App.palette_set(p.slice(0, 255), false)
	else:
		App.palette_set(_imp_colors, true)


# ---- export ------------------------------------------------------------------

var _export_kind := 0


func _export(id: int) -> void:
	_export_kind = id
	_export_dialog.filters = PackedStringArray([["*.png ; PNG"], ["*.hex ; Hex list"], ["*.gpl ; GIMP palette"]][id])
	_export_dialog.current_file = ["palette.png", "palette.hex", "palette.gpl"][id]
	_export_dialog.popup_centered_ratio(0.6)


func _on_export_file(path: String) -> void:
	var pal := App.project.palette
	match _export_kind:
		0:
			var img := Image.create(maxi(pal.size(), 1), 1, false, Image.FORMAT_RGBA8)
			for i in pal.size():
				img.set_pixel(i, 0, pal[i])
			img.save_png(path)
		1:
			var f := FileAccess.open(path, FileAccess.WRITE)
			for c in pal:
				f.store_line(c.to_html(false))
		2:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_line("GIMP Palette")
			f.store_line("Name: " + path.get_file().get_basename())
			f.store_line("Columns: 8")
			f.store_line("#")
			for c in pal:
				f.store_line("%3d %3d %3d\t%s" % [c.r8, c.g8, c.b8, c.to_html(false)])
	App.status.emit("Exported palette to " + path)
