class_name LayerSettingsPanel
extends ScrollContainer
## Per-layer render settings: tiling, cell style, features. Everything here is
## non-destructive; it only changes how the layer's cells are drawn.

var _box: VBoxContainer
var _pending := false
var _confirm: ConfirmationDialog
var _pending_tiling := ""


func _ready() -> void:
	name = "Layer Settings"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(UiKit.margin(_box, 4))
	(_box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Change tiling"
	_confirm.confirmed.connect(_apply_tiling)
	add_child(_confirm)
	App.document_changed.connect(_queue)
	App.active_layer_changed.connect(_queue)
	App.selection_changed.connect(func():
		var l := _l()
		if l and l.is_direction():
			_queue())
	_queue()


func _queue() -> void:
	if not _pending:
		_pending = true
		_build.call_deferred()


func _l() -> LayerData:
	return App.active_layer()


func _set_setting(key: String, v: Variant) -> void:
	var l := _l()
	if l == null:
		return
	if typeof(LayerData.DEFAULT_SETTINGS.get(key)) == TYPE_BOOL:
		v = bool(v)
	l.settings[key] = v
	App.layer_settings_changed.emit(l.id)


func _slider(text: String, key: String, minv: float, maxv: float, step: float) -> Control:
	var l := _l()
	return UiKit.slider_row(text, minv, maxv, step, float(l.setting(key)),
		func(v): _set_setting(key, int(v) if step >= 1.0 and typeof(LayerData.DEFAULT_SETTINGS.get(key)) == TYPE_INT else v),
		func(): App.begin_change(),
		func(): App.end_change(text))


func _check(text: String, key: String, tip := "") -> Control:
	var l := _l()
	return UiKit.toggle(text, bool(l.setting(key)), func(on):
		App.begin_change()
		_set_setting(key, on)
		App.end_change(text)
		_queue(), tip)


func _choice(text: String, key: String, items: Array) -> Control:
	var l := _l()
	var o := UiKit.option(items, int(l.setting(key)), func(i):
		App.begin_change()
		_set_setting(key, i)
		App.end_change(text)
		_queue())
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := UiKit.label(text)
	lab.custom_minimum_size.x = 96
	return UiKit.hbox([lab, o])


func _section(title: String) -> void:
	_box.add_child(HSeparator.new())
	_box.add_child(UiKit.header(title))


func _build() -> void:
	_pending = false
	for c in _box.get_children():
		c.queue_free()
	var l := _l()
	if l == null:
		return
	if l.is_direction():
		_build_direction(l)
		return
	_box.add_child(UiKit.label("Layer: " + l.name, true))

	# 1. Tiling
	_section("1 · Tiling")
	var ids := TilingRegistry.ids()
	var names: Array = []
	for id in ids:
		names.append(TilingRegistry.display_name(id))
	var opt := UiKit.option(names, ids.find(l.tiling_id), func(i):
		_pending_tiling = ids[i]
		_confirm.dialog_text = "Resample this layer's cells into the %s tiling?\n(One undo step; cells are mapped by position.)" % names[i]
		_confirm.popup_centered()
		_queue())
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(UiKit.hbox([UiKit.label("Tiling"), opt]))
	var t := App.tiling_of(l)
	for d in t.param_defs():
		var key: String = d.key
		_box.add_child(UiKit.slider_row(d.label, d.min, d.max, d.step, float(l.tiling_params.get(key, d.default)),
			func(v):
				l.tiling_params[key] = v
				App.layer_settings_changed.emit(l.id)
				App.layers_changed.emit(),
			func(): App.begin_change(),
			func(): App.end_change("Tiling " + d.label)))
	var info := UiKit.label("Rotation step %d°%s" % [int(t.rotation_step_deg()), " · staggered rows" if t.staggered_rows() else ""], true)
	_box.add_child(UiKit.hbox([info, UiKit.button("Shape Editor…", _open_shapes)]))

	# 2. Cell style
	_section("2 · Cell style")
	_box.add_child(_choice("Style", "style", LayerData.STYLE_NAMES))
	var style := int(l.setting("style"))
	if style != LayerData.Style.FLAT and style != LayerData.Style.MOSAIC:
		_box.add_child(_slider("Size", "dot_size", 0.05, 1.0, 0.01))
	if style == LayerData.Style.SVG_STAMP or _patterns_use_stamp(l):
		var stamps: Array = [["None (circle)", ""]]
		for id in App.project.shapes:
			if App.project.shapes[id].kind == "stamp":
				stamps.append([App.project.shapes[id].name, id])
		var cur := 0
		for i in stamps.size():
			if stamps[i][1] == str(l.setting("stamp_shape")):
				cur = i
		var so := UiKit.option(stamps.map(func(e): return e[0]), cur, func(i):
			App.begin_change()
			_set_setting("stamp_shape", stamps[i][1])
			App.end_change("SVG stamp shape"))
		so.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_child(UiKit.hbox([UiKit.label("Stamp shape"), so, UiKit.button("Edit…", _open_shapes)]))
	if style == LayerData.Style.CROSS_STITCH:
		_box.add_child(_slider("Thread", "stamp_thickness", 0.05, 1.0, 0.01))

	# 3. Features
	_section("3 · Features — Shape")
	_box.add_child(_check("Rounding", "rounding_on"))
	if l.setting("rounding_on"):
		_box.add_child(_slider("Corner radius", "rounding", 0.0, 1.0, 0.01))
		_box.add_child(_check("Color-aware (same colors merge)", "rounding_color_aware",
			"Same-colored neighbors merge into one shape; corners round only where the color changes"))
		if l.setting("rounding_color_aware"):
			_box.add_child(_choice("Corners", "rounding_inner", ["Outer only", "Inner + outer"]))
	_box.add_child(_check("Gap / grout", "gap_on"))
	if l.setting("gap_on"):
		_box.add_child(_slider("Gap", "gap", 0.0, 1.0, 0.01))
		_box.add_child(_check("Fill grout", "grout_on"))
		_box.add_child(UiKit.hbox([UiKit.label("Grout color"), UiKit.color_button(Color.html(l.setting("grout_color")), func(c):
			App.begin_change()
			_set_setting("grout_color", c.to_html(true))
			App.end_change("Grout color"))]))
	_box.add_child(_choice("Color edges", "boundary_mode", ["Hard edge", "Dithered transition"]))
	if int(l.setting("boundary_mode")) == 1:
		_box.add_child(_slider("Dither width", "boundary_width", 0.05, 1.0, 0.01))
	_box.add_child(_check("Jitter", "jitter_on", "The only source of per-cell random movement"))
	if l.setting("jitter_on"):
		_box.add_child(_choice("Driven by", "jitter_source", ["Random", "Flow (Direction Layer)", "Pattern (slot 1 value)"]))
		if int(l.setting("jitter_source")) == 1:
			_box.add_child(UiKit.label("Pushes cells along the layer chosen in 6 · Flow.", true))
		_box.add_child(_slider("Position", "jitter_pos", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Size", "jitter_size", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Rotation", "jitter_rot", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Seed", "jitter_seed", 0, 9999, 1))

	_build_crt(l)
	_build_patterns(l)
	_build_offset(l)
	_build_flow(l)


func _build_offset(l: LayerData) -> void:
	_section("5 · Offset")
	var base: Tiling = App.tiling_of(l)
	if base is OffsetTiling:
		base = (base as OffsetTiling).base
	var modes: Array = OffsetTiling.modes_for(base)
	var names: Array = modes.map(func(m): return OffsetTiling.MODE_NAMES[m])
	var cur := int(l.setting("offset_mode"))
	var o := UiKit.option(names, maxi(modes.find(cur), 0), func(i): App.set_layer_offset(l, modes[i]))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := UiKit.label("Offset")
	lab.custom_minimum_size.x = 96
	_box.add_child(UiKit.hbox([lab, o]))
	if cur != 0:
		_box.add_child(_slider("Amount (cells)", "offset_amount", 0.0, 1.0, 0.01))
	if modes.size() < OffsetTiling.MODE_NAMES.size():
		_box.add_child(UiKit.label("Brick modes hidden: this tiling is already staggered.", true))


func _build_crt(l: LayerData) -> void:
	_section("3 · Features — CRT")
	_box.add_child(_check("Scanlines", "scan_on"))
	if l.setting("scan_on"):
		_box.add_child(_slider("Thickness", "scan_thickness", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Darkness", "scan_dark", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Spacing px", "scan_spacing", 1.0, 32.0, 0.5))
	_box.add_child(_check("Phosphor mask", "mask_on"))
	if l.setting("mask_on"):
		_box.add_child(_choice("Mask", "mask_type", ["Aperture grille", "Slot mask", "Shadow mask"]))
		_box.add_child(_slider("Strength", "mask_strength", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Mask px", "mask_size", 0.25, 8.0, 0.25))
	_box.add_child(_check("Beam spot", "beam_on", "Brightness controls dot size: bright = wider, dark = narrower"))
	if l.setting("beam_on"):
		_box.add_child(_slider("Amount", "beam_amount", 0.0, 1.0, 0.01))
	_box.add_child(_check("Horizontal bleed", "bleed_on"))
	if l.setting("bleed_on"):
		_box.add_child(_slider("Bleed", "bleed", 0.0, 1.0, 0.01))


func _apply_tiling() -> void:
	var l := _l()
	if l == null or _pending_tiling == "" or _pending_tiling == l.tiling_id:
		return
	App.change_layer_tiling(l, _pending_tiling, TilingRegistry.default_params(_pending_tiling))
	_pending_tiling = ""


# ---- 4 · Patterns ------------------------------------------------------------

func _slot(i: int) -> Dictionary:
	return Patterns.slots(_l())[i]


func _pset(i: int, key: String, v: Variant) -> void:
	var l := _l()
	l.settings.patterns[i][key] = v
	App.layer_settings_changed.emit(l.id)


func _pslider(i: int, text: String, key: String, minv: float, maxv: float, step: float) -> Control:
	return UiKit.slider_row(text, minv, maxv, step, float(_slot(i)[key]),
		func(v): _pset(i, key, int(v) if step >= 1.0 else v),
		func(): App.begin_change(), func(): App.end_change("Pattern " + text))


func _prange(i: int, text: String, key: String, minv: float, maxv: float, step := 0.01) -> Control:
	var box := VBoxContainer.new()
	var r: Array = _slot(i)[key]
	box.add_child(UiKit.slider_row(text + " low", minv, maxv, step, float(r[0]),
		func(v):
			var a: Array = _slot(i)[key].duplicate()
			a[0] = v
			_pset(i, key, a),
		func(): App.begin_change(), func(): App.end_change("Pattern " + text)))
	box.add_child(UiKit.slider_row(text + " high", minv, maxv, step, float(r[1]),
		func(v):
			var a: Array = _slot(i)[key].duplicate()
			a[1] = v
			_pset(i, key, a),
		func(): App.begin_change(), func(): App.end_change("Pattern " + text)))
	return box


func _pchange(i: int, key: String, v: Variant, action: String) -> void:
	App.begin_change()
	_pset(i, key, v)
	App.end_change(action)
	_queue()


func _build_patterns(l: LayerData) -> void:
	_section("4 · Patterns")
	if not l.settings.has("patterns") or typeof(l.settings.patterns) != TYPE_ARRAY:
		l.settings["patterns"] = []
	var slots := Patterns.slots(l)
	for i in slots.size():
		_build_slot(l, i)
	if slots.size() < Patterns.MAX_SLOTS:
		_box.add_child(UiKit.button("+ Add pattern", func():
			App.begin_change()
			var sl := Patterns.default_slot()
			sl.seed = randi() % 10000
			l.settings.patterns.append(sl)
			App.layer_settings_changed.emit(l.id)
			App.end_change("Add pattern")
			_queue()))


func _build_slot(l: LayerData, i: int) -> void:
	var sl := _slot(i)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.19, 0.19, 0.23)
	sb.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	panel.add_child(v)
	_box.add_child(panel)
	var viewing := int(App.pattern_view.get(l.id, -1)) == i
	var title := UiKit.header("Pattern %d" % (i + 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.hbox([title,
		UiKit.toggle("Map view", viewing, func(on):
			App.pattern_view[l.id] = i if on else -1
			App.view_changed.emit()
			_queue(), "Show this pattern as grayscale over the cells (main canvas only)"),
		UiKit.button("Remove", func():
			App.begin_change()
			l.settings.patterns.remove_at(i)
			App.pattern_view.erase(l.id)
			App.layer_settings_changed.emit(l.id)
			App.end_change("Remove pattern")
			_queue())]))
	var src := int(sl.source)
	var so := UiKit.option(Patterns.SRC_NAMES, src, func(k): _pchange(i, "source", k, "Pattern source"))
	so.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.hbox([UiKit.label("Source"), so]))
	if Patterns.MODES.has(src):
		var mo := UiKit.option(Patterns.MODES[src], int(sl.mode), func(k): _pchange(i, "mode", k, "Pattern mode"))
		mo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiKit.hbox([UiKit.label("Kind"), mo]))
	var seed_row := _pslider(i, "Seed", "seed", 0, 9999, 1)
	seed_row.add_child(UiKit.button("Randomize", func(): _pchange(i, "seed", randi() % 10000, "Randomize pattern")))
	_place(v, seed_row)
	if src != Patterns.Src.BAYER and src != Patterns.Src.LIGHTNESS:
		_place(v, _pslider(i, "Scale (cells)", "scale", 0.25, 64.0, 0.25))
	_place(v, _pslider(i, "Contrast", "contrast", 0.0, 4.0, 0.01))
	if src in [Patterns.Src.HALFTONE, Patterns.Src.HATCHING, Patterns.Src.WEAVE, Patterns.Src.KNIT, Patterns.Src.WOOD, Patterns.Src.MARBLE]:
		_place(v, _pslider(i, "Angle°", "angle", -180.0, 180.0, 1.0))
	if src in [Patterns.Src.FRACTAL, Patterns.Src.WOOD, Patterns.Src.MARBLE]:
		_place(v, _pslider(i, "Octaves", "octaves", 1, 8, 1))
	if src in [Patterns.Src.WOOD, Patterns.Src.MARBLE]:
		_place(v, _pslider(i, "Turbulence", "turbulence", 0.0, 3.0, 0.01))
	if src == Patterns.Src.REACTION_DIFFUSION:
		var names: Array = ["Preset…"] + Patterns.RD_PRESETS.keys()
		var po := UiKit.option(names, 0, func(k):
			if k > 0:
				var fk: Array = Patterns.RD_PRESETS[names[k]]
				App.begin_change()
				_pset(i, "feed", fk[0])
				_pset(i, "kill", fk[1])
				App.end_change("Reaction-diffusion preset")
				_queue())
		v.add_child(UiKit.hbox([UiKit.label("Preset"), po]))
		_place(v, _pslider(i, "Feed", "feed", 0.0, 0.1, 0.0005))
		_place(v, _pslider(i, "Kill", "kill", 0.0, 0.1, 0.0005))
		_place(v, _pslider(i, "Iterations", "iterations", 10, 20000, 10))
	# Colour filter
	var cols: Array = sl.get("colors", [])
	var frow := HFlowContainer.new()
	frow.add_child(UiKit.label("Applies to: " + ("all colors" if cols.is_empty() else "%d colors" % cols.size()), true))
	var pal := App.project.palette
	for ci in pal.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = cols.has(ci + 1)
		b.custom_minimum_size = Vector2(16, 16)
		b.focus_mode = Control.FOCUS_NONE
		var st := StyleBoxFlat.new()
		st.bg_color = pal[ci]
		st.set_border_width_all(2 if cols.has(ci + 1) else 0)
		st.border_color = Color.WHITE
		for nm in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(nm, st)
		var idx := ci + 1
		b.pressed.connect(func():
			var c2: Array = _slot(i).get("colors", []).duplicate()
			if c2.has(idx):
				c2.erase(idx)
			else:
				c2.append(idx)
			_pchange(i, "colors", c2, "Pattern colors"))
		frow.add_child(b)
	v.add_child(frow)
	# What it drives
	v.add_child(UiKit.label("Drives:", true))
	var drives := int(sl.drives)
	for flag in Patterns.DRIVE_NAMES:
		var on: bool = (drives & int(flag)) != 0
		var f: int = flag
		v.add_child(UiKit.toggle(Patterns.DRIVE_NAMES[flag], on, func(t): _pchange(i, "drives", (int(_slot(i).drives) | f) if t else (int(_slot(i).drives) & ~f), "Pattern drive")))
		if not on:
			continue
		match flag:
			Patterns.Drive.STYLE:
				var cnt := int(sl.style_count)
				v.add_child(UiKit.hbox([UiKit.label("Styles"), UiKit.option(["2 (low / high)", "3 (low / mid / high)"], cnt - 2, func(k): _pchange(i, "style_count", k + 2, "Pattern styles"))]))
				for si in cnt:
					var sidx := si
					var labels := ["Low", "Mid", "High"] if cnt == 3 else ["Low", "High"]
					var o2 := UiKit.option(LayerData.STYLE_NAMES, int(sl.styles[si]), func(k):
						var a: Array = _slot(i).styles.duplicate()
						a[sidx] = k
						_pchange(i, "styles", a, "Pattern style map"))
					o2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					v.add_child(UiKit.hbox([UiKit.label("  " + labels[si]), o2]))
			Patterns.Drive.SIZE:
				_place(v, _prange(i, "Size", "size", 0.0, 2.0))
			Patterns.Drive.ROTATION:
				_place(v, _prange(i, "Turns ½", "rotation", -2.0, 2.0))
			Patterns.Drive.ROUNDING:
				_place(v, _prange(i, "Rounding", "rounding", 0.0, 1.0))
			Patterns.Drive.GAP:
				_place(v, _prange(i, "Gap", "gap", 0.0, 1.0))
			Patterns.Drive.JITTER:
				_place(v, _prange(i, "Jitter ×", "jitter", 0.0, 2.0))
			Patterns.Drive.PALETTE_SHIFT:
				_place(v, _prange(i, "Shift steps", "shift", -16.0, 16.0, 1.0))
			Patterns.Drive.VISIBILITY:
				_place(v, _pslider(i, "Hide below", "visibility", 0.0, 1.0, 0.01))
	v.add_child(UiKit.toggle("Fine texture inside cells", bool(sl.fine), func(t): _pchange(i, "fine", t, "Fine texture"),
		"Draw the pattern as a sub-cell texture (same seed and canvas coordinates at every scale)"))
	if sl.fine:
		_place(v, _pslider(i, "Texture amount", "fine_amount", 0.0, 1.0, 0.01))


func _place(parent: Control, c: Control) -> void:
	parent.add_child(c)


# ---- 6 · Flow ------------------------------------------------------------------

func _build_flow(l: LayerData) -> void:
	_section("6 · Flow")
	var dirs: Array = [["None", 0]]
	for d in App.project.layers:
		if d.is_direction():
			dirs.append([d.name, d.id])
	var dir_names: Array = dirs.map(func(e): return e[0])
	var cur := 0
	for i in dirs.size():
		if dirs[i][1] == int(l.setting("flow_layer")):
			cur = i
	var o := UiKit.option(dir_names, cur, func(i):
		App.begin_change()
		_set_setting("flow_layer", dirs[i][1])
		App.end_change("Follow direction layer")
		_queue())
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := UiKit.label("Follow")
	lab.custom_minimum_size.x = 96
	_box.add_child(UiKit.hbox([lab, o]))
	if dirs.size() == 1:
		_box.add_child(UiKit.label("Add a direction layer (+ Dir in Layers) and draw arrows.", true))
	if cur == 0:
		return
	_box.add_child(_slider("Flow strength", "flow_strength", 0.0, 1.0, 0.01))
	_box.add_child(UiKit.label("What follows the flow:", true))
	_box.add_child(_check("Stamp / brush dab rotation aligns", "flow_stamp_rot"))
	_box.add_child(_check("Cell rotation aligns", "flow_cell_rot"))
	_box.add_child(_check("Patterns bend and stretch along it", "flow_patterns"))
	_box.add_child(_check("Reaction-diffusion becomes directional", "flow_rd"))
	_box.add_child(UiKit.label("Jitter pushes along the flow when Jitter → Driven by is Flow.", true))
	_box.add_child(_check("Animated flow (patterns drift; frames precomputed)", "flow_animate"))
	if l.setting("flow_animate"):
		_box.add_child(_slider("Drift speed", "flow_speed", 0.0, 8.0, 0.05))


# ---- direction layer settings ---------------------------------------------------

func _dset(key: String, v: Variant) -> void:
	var l := _l()
	var d: Dictionary = l.settings.get("dir", {}).duplicate()
	d[key] = v
	l.settings["dir"] = d
	App.layer_settings_changed.emit(l.id)


func _dval(key: String) -> Variant:
	var d := DirStroke.DEFAULT_SETTINGS.duplicate()
	d.merge(_l().settings.get("dir", {}), true)
	return d[key]


func _dslider(text: String, key: String, minv: float, maxv: float, step: float) -> Control:
	return UiKit.slider_row(text, minv, maxv, step, float(_dval(key)), func(v): _dset(key, v),
		func(): App.begin_change(), func(): App.end_change(text))


func _build_direction(l: LayerData) -> void:
	_box.add_child(UiKit.header("Direction layer · " + l.name))
	var info := UiKit.label("Tools: Arrow (A), Curve (C), Bezier (K: click to add points, drag for handles, Enter or double-click to finish), Edit (N: drag points, handles or whole strokes). Right-click a stroke to delete it.", true)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(info)
	_section("New strokes")
	var to := UiKit.option(DirStroke.TYPE_NAMES, int(_dval("new_type")), func(i):
		App.begin_change()
		_dset("new_type", i)
		App.end_change("Stroke type"))
	to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(UiKit.hbox([UiKit.label("Type (Arrow tool)"), to]))
	_box.add_child(_dslider("Radius (cells)", "new_radius", 0.0, 128.0, 0.5))
	_box.add_child(_dslider("Strength", "new_strength", 0.0, 4.0, 0.01))
	var strokes := l.strokes_at(App.frame)
	if App.dir_selected >= 0 and App.dir_selected < strokes.size():
		var i: int = App.dir_selected
		var st: Dictionary = strokes[i]
		_section("Selected stroke")
		var cs := float(App.project.cell_size)
		var tsel := UiKit.option(DirStroke.TYPE_NAMES, DirStroke.TYPES.find(st.type), func(k):
			App.perform("Stroke type", func(): l.strokes_at(App.frame)[i].type = DirStroke.TYPES[k])
			_queue())
		tsel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_child(UiKit.hbox([UiKit.label("Type"), tsel]))
		_box.add_child(UiKit.slider_row("Radius (cells)", 0.0, 128.0, 0.5, float(st.radius) / cs,
			func(v):
				l.strokes_at(App.frame)[i].radius = v * cs
				App.layer_settings_changed.emit(l.id),
			func(): App.begin_change(), func(): App.end_change("Stroke radius")))
		_box.add_child(UiKit.slider_row("Strength", 0.0, 4.0, 0.01, float(st.strength),
			func(v):
				l.strokes_at(App.frame)[i].strength = v
				App.layer_settings_changed.emit(l.id),
			func(): App.begin_change(), func(): App.end_change("Stroke strength")))
		_box.add_child(UiKit.hbox([
			UiKit.button("Reverse", func(): App.perform("Reverse stroke", func(): l.strokes_at(App.frame)[i] = DirStroke.reversed(l.strokes_at(App.frame)[i]))),
			UiKit.button("Delete", func():
				App.perform("Delete stroke", func():
					l.strokes_at(App.frame).remove_at(i)
					App.dir_selected = -1)
				_queue()),
		]))
	_section("Field")
	_box.add_child(_dslider("Smoothing (cells)", "smoothing", 0.25, 32.0, 0.25))
	_box.add_child(UiKit.toggle("Default direction where no strokes reach", bool(_dval("default_on")), func(on):
		App.begin_change()
		_dset("default_on", on)
		App.end_change("Default direction")
		_queue()))
	if _dval("default_on"):
		_box.add_child(_dslider("Default angle°", "default_angle", -180.0, 180.0, 1.0))
	var disp := UiKit.option(["Hidden", "Arrows", "Streamlines"], int(_dval("field_display")), func(k):
		App.begin_change()
		_dset("field_display", k)
		App.end_change("Field display"))
	disp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(UiKit.hbox([UiKit.label("Show field"), disp]))
	_section("Import")
	_box.add_child(UiKit.button("Import SVG paths as strokes…", func(): _svg_dialog().popup_centered_ratio(0.6),
		"Each path becomes a curve; direction follows the path from start to end"))
	_section("Direction presets")
	var flow := HFlowContainer.new()
	for pn in DirStroke.PRESETS:
		var pname: String = pn
		flow.add_child(UiKit.button(pname, func():
			App.perform("Direction preset: " + pname, func():
				var arr := l.strokes_at(App.frame)
				arr.clear()
				arr.append_array(DirStroke.preset(pname, App.project.canvas_px(), randi() % 1000)))
			_queue(), "Replaces this frame's strokes"))
	_box.add_child(flow)



func _open_shapes() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if main and main.has_method("open_shape_editor"):
		main.open_shape_editor()


func _patterns_use_stamp(l: LayerData) -> bool:
	for sl in Patterns.slots(l):
		if (int(sl.drives) & Patterns.Drive.STYLE) != 0 and (sl.styles as Array).has(LayerData.Style.SVG_STAMP):
			return true
	return false



var _svg_dlg: FileDialog


func _svg_dialog() -> FileDialog:
	if _svg_dlg == null:
		_svg_dlg = FileDialog.new()
		_svg_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_svg_dlg.access = FileDialog.ACCESS_FILESYSTEM
		_svg_dlg.filters = PackedStringArray(["*.svg ; SVG"])
		_svg_dlg.file_selected.connect(_import_svg_strokes)
		add_child(_svg_dlg)
	return _svg_dlg


## SVG paths -> direction strokes, fitted into the canvas.
func _import_svg_strokes(path: String) -> void:
	var l := _l()
	var parsed := Svg.parse_file(path)
	if l == null or not l.is_direction() or parsed.paths.is_empty():
		App.status.emit("No paths found")
		return
	var b: Rect2 = parsed.bounds
	var px := App.project.canvas_px()
	var k := minf(px.x * 0.9 / maxf(b.size.x, 1e-6), px.y * 0.9 / maxf(b.size.y, 1e-6))
	var off := px * 0.5 - b.get_center() * k
	App.perform("Import SVG strokes", func():
		for pa in parsed.paths:
			var pts := PackedVector2Array()
			for v in pa.points:
				pts.append(v * k + off)
			l.strokes_at(App.frame).append(DirStroke.make("bezier", "path", pts, 0.0, 1.0)))
