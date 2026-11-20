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
		_box.add_child(UiKit.header("Direction layer"))
		var info := UiKit.label("Draw arrows and curves with the left button; right button erases strokes. Other layers will be able to follow this flow.", true)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(info)
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
	_box.add_child(info)

	# 2. Cell style
	_section("2 · Cell style")
	_box.add_child(_choice("Style", "style", LayerData.STYLE_NAMES))
	var style := int(l.setting("style"))
	if style != LayerData.Style.FLAT and style != LayerData.Style.MOSAIC:
		_box.add_child(_slider("Size", "dot_size", 0.05, 1.0, 0.01))
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
		_box.add_child(_choice("Driven by", "jitter_source", ["Random"]))
		_box.add_child(_slider("Position", "jitter_pos", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Size", "jitter_size", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Rotation", "jitter_rot", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Seed", "jitter_seed", 0, 9999, 1))

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
