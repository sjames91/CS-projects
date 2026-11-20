extends Control
## Builds the editor window from Control nodes and wires menus + shortcuts.

var hub: RenderHub
var canvas: CanvasView
var preview: PreviewPanel
var timeline: TimelinePanel
var right_split: VSplitContainer
var main_split: HSplitContainer
var _tool_buttons := {}
var _status: Label
var _busy: Label
var _msg := ""
var _msg_time := 0.0
var _opts_box: HBoxContainer
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _export_file: FileDialog
var _export_win: AcceptDialog
var _export_opts := {"scale": 1, "what": 0}
var _canvas_win: ConfirmationDialog
var _canvas_vals := {}
var _canvas_is_new := false
var _quit_confirm: ConfirmationDialog
var _warn: AcceptDialog
var _menus := {}


func _ready() -> void:
	get_tree().auto_accept_quit = false
	theme = _make_theme()
	hub = RenderHub.new()
	add_child(hub)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.13, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	add_child(root)
	root.add_child(_build_menu())
	_opts_box = HBoxContainer.new()
	root.add_child(UiKit.margin(_opts_box, 3))
	main_split = HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main_split)
	var left := HBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_child(left)
	left.add_child(_build_toolbox())
	canvas = CanvasView.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(canvas)
	canvas.setup(hub)
	right_split = VSplitContainer.new()
	right_split.custom_minimum_size.x = 380
	main_split.add_child(right_split)
	preview = PreviewPanel.new()
	preview.custom_minimum_size.y = 180
	preview.setup(hub, canvas)
	preview.navigate.connect(canvas.center_on)
	right_split.add_child(preview)
	var lower := VSplitContainer.new()
	right_split.add_child(lower)
	var pal := PalettePanel.new()
	pal.custom_minimum_size.y = 120
	lower.add_child(pal)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(LayersPanel.new())
	tabs.add_child(LayerSettingsPanel.new())
	lower.add_child(tabs)
	timeline = TimelinePanel.new()
	timeline.onion_changed.connect(canvas.set_onion)
	root.add_child(UiKit.margin(timeline, 3))
	var status_bar := HBoxContainer.new()
	_status = UiKit.label("", true)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(_status)
	_busy = UiKit.label("● rendering", false)
	_busy.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_busy.visible = false
	status_bar.add_child(_busy)
	root.add_child(UiKit.margin(status_bar, 3))
	hub.busy_changed.connect(func(b): _busy.visible = b)
	_build_dialogs()
	App.tool_changed.connect(_refresh_tool_ui)
	App.view_changed.connect(_refresh_tool_ui)
	App.status.connect(func(m):
		_msg = m
		_msg_time = 3.0)
	App.title_changed.connect(_update_title)
	_refresh_tool_ui()
	_update_title()
	right_split.split_offset = 60
	await get_tree().process_frame
	main_split.split_offset = -40


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.15, 0.15, 0.18)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


# ---- menus -------------------------------------------------------------------

func _menu(bar: MenuBar, title: String, items: Array) -> void:
	var pm := PopupMenu.new()
	pm.name = title
	for it in items:
		if it.is_empty():
			pm.add_separator()
			continue
		var id := pm.item_count
		if it.size() > 3 and it[3] == "check":
			pm.add_check_item(it[0], id)
		else:
			pm.add_item(it[0], id)
		if it[1] != 0:
			pm.set_item_accelerator(pm.get_item_index(id), it[1])
		pm.set_item_metadata(pm.get_item_index(id), it[2])
	pm.id_pressed.connect(func(id): (pm.get_item_metadata(pm.get_item_index(id)) as Callable).call())
	bar.add_child(pm)
	_menus[title] = pm


func _build_menu() -> MenuBar:
	var bar := MenuBar.new()
	var C := KEY_MASK_CMD_OR_CTRL
	_menu(bar, "File", [
		["New…", C | KEY_N, _new_dialog],
		["Open…", C | KEY_O, func(): _open_dialog.popup_centered_ratio(0.6)],
		["Save", C | KEY_S, save],
		["Save As…", C | KEY_MASK_SHIFT | KEY_S, func(): _save_dialog.popup_centered_ratio(0.6)],
		[],
		["Export PNG…", C | KEY_E, func(): _export_win.popup_centered()],
		[],
		["Quit", C | KEY_Q, _request_quit],
	])
	_menu(bar, "Edit", [
		["Undo", C | KEY_Z, func(): App.do_undo()],
		["Redo", C | KEY_MASK_SHIFT | KEY_Z, func(): App.do_redo()],
		[],
		["Cut", C | KEY_X, func(): SelectionOps.cut()],
		["Copy", C | KEY_C, func(): SelectionOps.copy()],
		["Paste", C | KEY_V, _paste],
		["Delete selected", KEY_DELETE, func(): SelectionOps.delete_selected()],
		[],
		["Select all", C | KEY_A, func(): SelectionOps.select_all()],
		["Deselect", C | KEY_D, func(): App.clear_selection()],
		[],
		["Flip horizontal", KEY_H, func(): SelectionOps.transform("flip_h")],
		["Flip vertical", KEY_MASK_SHIFT | KEY_H, func(): SelectionOps.transform("flip_v")],
		["Rotate clockwise (tiling step)", KEY_R, func(): SelectionOps.transform("rot_cw")],
		["Rotate counter-clockwise", KEY_MASK_SHIFT | KEY_R, func(): SelectionOps.transform("rot_ccw")],
	])
	_menu(bar, "Canvas", [
		["Canvas size / cell size…", C | KEY_MASK_ALT | KEY_C, _resize_dialog],
		[],
		["Grid lines", C | KEY_G, func(): App.set_view("grid_on", not App.grid_on), "check"],
		["Tile preview (3×3)", KEY_T, func(): _toggle_tile(), "check"],
		["Wrap-around drawing", KEY_MASK_SHIFT | KEY_T, func(): App.set_view("wrap_draw", not App.wrap_draw), "check"],
		[],
		["Mirror: cycle off / H / V / both", KEY_Y, func(): App.set_view("mirror", (App.mirror + 1) % 4)],
	])
	_menu(bar, "View", [
		["Render: full result / raw cells   (Tab)", 0, func(): App.set_view("render_on", not App.render_on), "check"],
		["Preview panel", KEY_P, _toggle_preview, "check"],
		["Preview with Palette Lock", KEY_MASK_SHIFT | KEY_P, func(): App.set_view("preview_lock", not App.preview_lock), "check"],
		[],
		["Fit canvas", C | KEY_0, func(): canvas.fit_view()],
		["Zoom in", KEY_EQUAL, func(): canvas.zoom_at(canvas.size * 0.5, 1.25)],
		["Zoom out", KEY_MINUS, func(): canvas.zoom_at(canvas.size * 0.5, 0.8)],
	])
	_menu(bar, "Animation", [
		["Play / pause", KEY_ENTER, func(): timeline.toggle_play()],
		["Previous frame", KEY_COMMA, func(): timeline.step(-1)],
		["Next frame", KEY_PERIOD, func(): timeline.step(1)],
	])
	_menu(bar, "Help", [
		["Shortcuts…", KEY_F1, _show_help],
	])
	App.view_changed.connect(_sync_checks)
	_sync_checks()
	return bar


func _sync_checks() -> void:
	var cv: PopupMenu = _menus["Canvas"]
	cv.set_item_checked(2, App.grid_on)
	cv.set_item_checked(3, App.tile_preview)
	cv.set_item_checked(4, App.wrap_draw)
	var v: PopupMenu = _menus["View"]
	v.set_item_checked(0, App.render_on)
	v.set_item_checked(1, preview == null or preview.visible)
	v.set_item_checked(2, App.preview_lock)


func _toggle_tile() -> void:
	App.set_view("tile_preview", not App.tile_preview)
	canvas.fit_view()


func _toggle_preview() -> void:
	preview.visible = not preview.visible
	_sync_checks()


func _paste() -> void:
	var hp := App.hover_canvas_point
	var px := App.project.canvas_px()
	if Rect2(Vector2.ZERO, px).has_point(hp):
		SelectionOps.paste(hp)
	else:
		SelectionOps.paste()


func _input(event: InputEvent) -> void:
	# Tab would otherwise move GUI focus; it is the render toggle.
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_TAB:
		var focus := get_viewport().gui_get_focus_owner()
		if not (focus is LineEdit or focus is TextEdit):
			App.set_view("render_on", not App.render_on)
			get_viewport().set_input_as_handled()


func _shortcut_input(event: InputEvent) -> void:
	# Tool keys (no modifiers). Menu accelerators handle the rest.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return
	for id in ToolController.TOOLS:
		if ToolController.TOOLS[id].key == k.keycode and not k.shift_pressed:
			App.set_tool(id)
			get_viewport().set_input_as_handled()
			return
	if k.keycode == KEY_BRACKETLEFT:
		App.tool_opts.brush = maxi(1, App.tool_opts.brush - 1)
		_refresh_tool_ui()
	elif k.keycode == KEY_BRACKETRIGHT:
		App.tool_opts.brush = mini(32, App.tool_opts.brush + 1)
		_refresh_tool_ui()


# ---- toolbox & options --------------------------------------------------------

func _build_toolbox() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 112
	for id in ToolController.ORDER:
		var info: Dictionary = ToolController.TOOLS[id]
		var b := Button.new()
		b.text = "%s  %s" % [info.name, OS.get_keycode_string(info.key)]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s (%s)" % [info.name, OS.get_keycode_string(info.key)]
		var tid: String = id
		b.pressed.connect(func(): App.set_tool(tid))
		box.add_child(b)
		_tool_buttons[id] = b
	box.add_child(HSeparator.new())
	var hint := UiKit.label("Left: draw\nRight: erase\nWheel: zoom\nMiddle: pan", true)
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


func _refresh_tool_ui() -> void:
	for id in _tool_buttons:
		_tool_buttons[id].set_pressed_no_signal(id == App.tool)
	for c in _opts_box.get_children():
		c.queue_free()
	var o := App.tool_opts
	var t := App.tool
	_opts_box.add_child(UiKit.label(ToolController.TOOLS[t].name + "  "))
	if t in ["pencil", "eraser", "line", "rect", "ellipse"]:
		var bs := SpinBox.new()
		bs.min_value = 1
		bs.max_value = 32
		bs.value = o.brush
		bs.tooltip_text = "Brush size in cells ([ and ])"
		bs.value_changed.connect(func(v): App.tool_opts.brush = int(v))
		_opts_box.add_child(UiKit.label("Brush"))
		_opts_box.add_child(bs)
	if t in ["rect", "ellipse"]:
		_opts_box.add_child(UiKit.toggle("Filled", o.filled, func(on): App.tool_opts.filled = on, "Shift = square/circle, Ctrl = from center"))
	if t == "fill":
		_opts_box.add_child(UiKit.toggle("Global (all matching)", o.fill_global, func(on): App.tool_opts.fill_global = on, "Shift-click also fills globally"))
		_opts_box.add_child(_tol_slider("fill tolerance", "tolerance"))
	if t == "wand":
		_opts_box.add_child(UiKit.toggle("Global", o.wand_global, func(on): App.tool_opts.wand_global = on))
		_opts_box.add_child(_tol_slider("wand tolerance", "wand_tolerance"))
	if t in ["select_rect", "lasso", "wand"]:
		_opts_box.add_child(UiKit.label("Shift: add · Ctrl: subtract", true))
	if t == "move":
		_opts_box.add_child(UiKit.label("Drag moves the selection (or the whole layer) · Alt: copy", true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opts_box.add_child(sp)
	_opts_box.add_child(UiKit.option(["Mirror off", "Mirror H", "Mirror V", "Mirror both"], App.mirror, func(i): App.set_view("mirror", i)))
	_opts_box.add_child(UiKit.toggle("Wrap", App.wrap_draw, func(on): App.set_view("wrap_draw", on), "Strokes crossing an edge continue on the other side"))
	_opts_box.add_child(UiKit.toggle("Tile 3×3", App.tile_preview, func(_on): _toggle_tile()))
	_opts_box.add_child(UiKit.toggle("Grid", App.grid_on, func(on): App.set_view("grid_on", on)))
	var rt := UiKit.toggle("Render", App.render_on, func(on): App.set_view("render_on", on),
		"ON: full result. OFF: only the selected layer's raw cells (Tab)")
	_opts_box.add_child(rt)


func _tol_slider(tip: String, key: String) -> Control:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 0.5
	s.step = 0.005
	s.value = App.tool_opts[key]
	s.custom_minimum_size.x = 120
	s.tooltip_text = "Tolerance (OKLab distance)"
	s.value_changed.connect(func(v): App.tool_opts[key] = v)
	return UiKit.hbox([UiKit.label("Tolerance"), s])


func _process(dt: float) -> void:
	if _msg_time > 0.0:
		_msg_time -= dt
	var l := App.active_layer()
	var parts: Array[String] = []
	var hp := App.hover_canvas_point
	if l and not l.is_direction() and hp.x > -1e8:
		var t := App.tiling_of(l)
		var c := t.point_to_cell(hp)
		if t.in_grid(c):
			parts.append("cell %d,%d" % [c.x, c.y])
	parts.append("zoom %d%%" % int(canvas.zoom * 100.0))
	parts.append("%d×%d cells @ %dpx" % [App.project.canvas_cells.x, App.project.canvas_cells.y, App.project.cell_size])
	if l:
		parts.append(("direction layer" if l.is_direction() else TilingRegistry.display_name(l.tiling_id)) + (" · locked" if l.locked else ""))
	parts.append("frame %d/%d" % [App.frame + 1, App.project.frame_count])
	if not App.render_on:
		parts.append("RAW")
	if _msg_time > 0.0:
		parts.append("— " + _msg)
	_status.text = "  ·  ".join(parts)


# ---- files -----------------------------------------------------------------

func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.filters = PackedStringArray(["*.tessera ; Tessera project", "*.json ; JSON"])
	_open_dialog.file_selected.connect(open_file)
	add_child(_open_dialog)
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.filters = PackedStringArray(["*.tessera ; Tessera project"])
	_save_dialog.file_selected.connect(save_to)
	add_child(_save_dialog)
	_export_file = FileDialog.new()
	_export_file.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_file.access = FileDialog.ACCESS_FILESYSTEM
	_export_file.filters = PackedStringArray(["*.png ; PNG"])
	_export_file.file_selected.connect(func(p): export_png(p))
	add_child(_export_file)
	_warn = AcceptDialog.new()
	_warn.title = "Notice"
	add_child(_warn)
	_quit_confirm = ConfirmationDialog.new()
	_quit_confirm.dialog_text = "You have unsaved changes. Quit anyway?"
	_quit_confirm.ok_button_text = "Quit without saving"
	_quit_confirm.confirmed.connect(func(): get_tree().quit())
	add_child(_quit_confirm)
	_build_export_win()
	_build_canvas_win()


func _update_title() -> void:
	var nm := App.project_path.get_file() if App.project_path != "" else "Untitled"
	get_window().title = "Tessera — %s%s" % [nm, " *" if App.dirty else ""]


func save() -> void:
	if App.project_path == "":
		_save_dialog.popup_centered_ratio(0.6)
	else:
		save_to(App.project_path)


func save_to(path: String) -> void:
	if path.get_extension() == "":
		path += ".tessera"
	var err := ProjectIO.save(App.project, path)
	if err != OK:
		_alert("Could not save: %s" % error_string(err))
		return
	App.project_path = path
	App.dirty = false
	App.status.emit("Saved " + path.get_file())
	_update_title()


func open_file(path: String) -> void:
	var res := ProjectIO.load_file(path)
	if res.has("error"):
		_alert(res.error)
		return
	App.new_project(res.project, path)
	canvas.fit_view()
	if not res.warnings.is_empty():
		_alert("\n".join(res.warnings))


func _alert(text: String) -> void:
	_warn.dialog_text = text
	_warn.popup_centered()


func _request_quit() -> void:
	if App.dirty:
		_quit_confirm.popup_centered()
	else:
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()


# ---- export ------------------------------------------------------------------

func _build_export_win() -> void:
	_export_win = AcceptDialog.new()
	_export_win.title = "Export PNG"
	_export_win.ok_button_text = "Choose file…"
	var v := VBoxContainer.new()
	var sc := SpinBox.new()
	sc.min_value = 1
	sc.max_value = 16
	sc.value = 1
	sc.value_changed.connect(func(x): _export_opts.scale = int(x))
	v.add_child(UiKit.hbox([UiKit.label("Scale ×"), sc, UiKit.label("(1 = cell size px per cell)", true)]))
	v.add_child(UiKit.option(["Current frame", "All frames (numbered PNGs)", "All frames (horizontal sprite sheet)"], 0, func(i): _export_opts.what = i))
	v.add_child(HSeparator.new())
	var lock := App.project.palette_lock
	v.add_child(UiKit.header("Palette Lock (final output only)"))
	v.add_child(UiKit.toggle("Snap to palette (OKLab)", lock.get("enabled", false), func(on): _set_lock("enabled", on)))
	v.add_child(UiKit.toggle("Dither at the snap step", lock.get("dither", false), func(on): _set_lock("dither", on)))
	v.add_child(UiKit.slider_row("Dither strength", 0, 1, 0.01, lock.get("strength", 0.5), func(x): _set_lock("strength", x), func(): pass, func(): pass))
	_export_win.add_child(v)
	_export_win.confirmed.connect(func():
		_export_file.current_file = (App.project_path.get_file().get_basename() if App.project_path != "" else "artwork") + ".png"
		_export_file.popup_centered_ratio(0.6))
	add_child(_export_win)


func _set_lock(key: String, v: Variant) -> void:
	App.project.palette_lock[key] = v
	App.dirty = true
	App.view_changed.emit()


## Final output for one frame: every visible layer rendered fresh at export
## resolution, composited on the GPU, then Palette Lock (if on) on the GPU.
func render_frame_image(frame: int, scale: int) -> Image:
	var px := App.project.canvas_px()
	var out_size := Vector2i(px * scale)
	var textures := {}
	for l in App.project.layers:
		if l.is_direction() or not App.layer_shown(l):
			continue
		var limg: Image = await hub.render_layer_image(l, frame, out_size)
		textures[l.id] = ImageTexture.create_from_image(limg)
	var cv := CompositeView.new()
	cv.texture_override = textures
	cv.frame_override = frame
	cv.size = out_size
	cv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(cv)
	cv.hub = hub
	cv.set_view(float(scale), Vector2.ZERO)
	cv.rebuild()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := cv.get_texture().get_image()
	cv.queue_free()
	var lock := App.project.palette_lock
	if lock.get("enabled", false):
		img = Gpu.palette_snap(img, App.project.palette, lock.get("dither", false), lock.get("strength", 0.5))
	return img


func export_png(path: String) -> void:
	if path.get_extension() == "":
		path += ".png"
	var scale: int = _export_opts.scale
	var n := App.project.frame_count
	_busy.visible = true
	match int(_export_opts.what):
		0:
			var img: Image = await render_frame_image(App.frame, scale)
			img.save_png(path)
		1:
			for f in n:
				var img: Image = await render_frame_image(f, scale)
				img.save_png("%s_%03d.png" % [path.get_basename(), f + 1])
		2:
			var first: Image = await render_frame_image(0, scale)
			var sheet := Image.create(first.get_width() * n, first.get_height(), false, first.get_format())
			sheet.blit_rect(first, Rect2i(Vector2i.ZERO, first.get_size()), Vector2i.ZERO)
			for f in range(1, n):
				var img: Image = await render_frame_image(f, scale)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(first.get_width() * f, 0))
			sheet.save_png(path)
	_busy.visible = hub.is_busy()
	App.status.emit("Exported " + path.get_file())


# ---- canvas size / new -------------------------------------------------------

func _build_canvas_win() -> void:
	_canvas_win = ConfirmationDialog.new()
	_canvas_win.confirmed.connect(_apply_canvas)
	var v := VBoxContainer.new()
	var g := GridContainer.new()
	g.columns = 2
	for key in ["width", "height", "cell"]:
		var sb := SpinBox.new()
		sb.min_value = 1 if key != "cell" else 2
		sb.max_value = 1024 if key != "cell" else 128
		sb.name = key
		sb.value_changed.connect(func(x): _canvas_vals[key] = int(x))
		g.add_child(UiKit.label({"width": "Width (cells)", "height": "Height (cells)", "cell": "Cell size (px)"}[key]))
		g.add_child(sb)
	v.add_child(g)
	var anchor_label := UiKit.label("Anchor (resize only)")
	anchor_label.name = "anchor_label"
	v.add_child(anchor_label)
	var ag := GridContainer.new()
	ag.name = "anchors"
	ag.columns = 3
	var group := ButtonGroup.new()
	for y in 3:
		for x in 3:
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.custom_minimum_size = Vector2(28, 28)
			b.text = "●" if x == 1 and y == 1 else "·"
			b.button_pressed = x == 1 and y == 1
			var a := Vector2(x * 0.5, y * 0.5)
			b.pressed.connect(func(): _canvas_vals.anchor = a)
			ag.add_child(b)
	v.add_child(ag)
	_canvas_win.add_child(v)
	add_child(_canvas_win)


func _show_canvas_win(is_new: bool) -> void:
	_canvas_is_new = is_new
	_canvas_win.title = "New project" if is_new else "Canvas size"
	_canvas_vals = {"width": App.project.canvas_cells.x, "height": App.project.canvas_cells.y, "cell": App.project.cell_size, "anchor": Vector2(0.5, 0.5)}
	var g: GridContainer = _canvas_win.get_child(0).get_child(0)
	for key in ["width", "height", "cell"]:
		(g.get_node(key) as SpinBox).set_value_no_signal(_canvas_vals[key])
	_canvas_win.get_child(0).get_node("anchors").visible = not is_new
	_canvas_win.get_child(0).get_node("anchor_label").visible = not is_new
	_canvas_win.popup_centered()


func _new_dialog() -> void:
	_show_canvas_win(true)


func _resize_dialog() -> void:
	_show_canvas_win(false)


func _apply_canvas() -> void:
	var cells := Vector2i(_canvas_vals.width, _canvas_vals.height)
	if _canvas_is_new:
		var p := ProjectData.new()
		p.canvas_cells = cells
		p.cell_size = _canvas_vals.cell
		p.palette = App.project.palette.duplicate()
		p.add_layer("Background")
		App.new_project(p)
	else:
		App.resize_canvas(cells, _canvas_vals.cell, _canvas_vals.anchor)
	canvas.fit_view()


func _show_help() -> void:
	var lines := ["Tools:"]
	for id in ToolController.ORDER:
		lines.append("  %s — %s" % [OS.get_keycode_string(ToolController.TOOLS[id].key), ToolController.TOOLS[id].name])
	lines.append_array([
		"",
		"Left drag: draw · Right drag: erase (any tool) · Alt+click (pencil): pick color",
		"Wheel: zoom at cursor · Middle drag or Space+drag: pan",
		"[ / ]: brush size · Shift: constrain shapes · Ctrl: shape from center",
		"Tab: render toggle (full result / raw cells) · Ctrl+G: grid · T: tile preview · Shift+T: wrap drawing",
		"Y: cycle mirror · H / Shift+H: flip · R / Shift+R: rotate by the tiling's step",
		"Ctrl+C / X / V: copy, cut, paste · Delete: clear selection · Ctrl+A / Ctrl+D: select all / none",
		"Ctrl+Z / Ctrl+Shift+Z: undo / redo · P: preview panel · Shift+P: palette-locked preview",
		"Enter: play · , / .: step frames",
	])
	_alert("\n".join(lines))
