class_name DisplayPanel
extends ScrollContainer
## Global Display stack: applied once to the final composite, then Palette
## Lock, then export. Never on raw-cells view.

var _box: VBoxContainer
var _pending := false


func _ready() -> void:
	name = "Display"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := UiKit.margin(_box, 4)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(m)
	App.document_changed.connect(_queue)
	_queue()


func _queue() -> void:
	if not _pending:
		_pending = true
		_build.call_deferred()


func _set_display(key: String, v: Variant) -> void:
	App.project.display[key] = v
	App.view_changed.emit()


func _slider(text: String, key: String, minv: float, maxv: float, step: float) -> Control:
	var d := DisplayStack.settings(App.project)
	return UiKit.slider_row(text, minv, maxv, step, float(d[key]), func(v): _set_display(key, v),
		func(): App.begin_change(), func(): App.end_change("Display " + text))


func _check(text: String, key: String) -> Control:
	var d := DisplayStack.settings(App.project)
	return UiKit.toggle(text, bool(d[key]), func(on):
		App.begin_change()
		_set_display(key, on)
		App.end_change("Display " + text)
		_queue())


func _build() -> void:
	_pending = false
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(UiKit.header("Display stack (whole image)"))
	_box.add_child(UiKit.label("Order: layers → Display → Palette Lock → export", true))
	var names: Array = ["Choose preset…"] + DisplayStack.PRESETS.keys()
	var crt_too := {"on": true}
	var preset := UiKit.option(names, 0, func(i):
		if i > 0:
			_apply_preset(names[i], crt_too.on))
	preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(UiKit.hbox([UiKit.label("Preset"), preset]))
	_box.add_child(UiKit.toggle("Also set suggested CRT features on the selected layer", true, func(on): crt_too.on = on))
	var d := DisplayStack.settings(App.project)
	_box.add_child(HSeparator.new())
	_box.add_child(_check("Screen curvature", "curv_on"))
	if d.curv_on:
		_box.add_child(_slider("Curvature", "curvature", 0.0, 0.5, 0.005))
	_box.add_child(_check("Vignette", "vig_on"))
	if d.vig_on:
		_box.add_child(_slider("Vignette", "vignette", 0.0, 1.0, 0.01))
	_box.add_child(_check("Bloom / glow", "bloom_on"))
	if d.bloom_on:
		_box.add_child(_slider("Threshold", "bloom_threshold", 0.0, 1.0, 0.01))
		_box.add_child(_slider("Radius px", "bloom_radius", 1.0, 32.0, 0.5))
		_box.add_child(_slider("Intensity", "bloom_intensity", 0.0, 2.0, 0.01))
	_box.add_child(_check("Chromatic aberration", "chroma_on"))
	if d.chroma_on:
		_box.add_child(_slider("Amount px", "chroma", 0.0, 8.0, 0.1))
	_box.add_child(_check("Interlace flicker (animated)", "interlace_on"))
	if d.interlace_on:
		_box.add_child(_slider("Flicker", "interlace", 0.0, 1.0, 0.01))
	_box.add_child(_check("Static noise (animated)", "noise_on"))
	if d.noise_on:
		_box.add_child(_slider("Noise", "noise", 0.0, 0.5, 0.005))


func _apply_preset(preset_name: String, with_crt: bool) -> void:
	var pr: Dictionary = DisplayStack.PRESETS[preset_name]
	var l := App.active_layer()
	App.perform("Display preset: " + preset_name, func():
		var d := DisplayStack.DEFAULTS.duplicate()
		d.merge(pr.display, true)
		App.project.display = d
		if with_crt and l and not l.is_direction():
			for k in pr.crt:
				l.settings[k] = pr.crt[k])
