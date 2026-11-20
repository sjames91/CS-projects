class_name LibraryPanel
extends ScrollContainer
## Presets (built-in + user) and the user library. Presets apply settings
## only; they never paint cells.

var _box: VBoxContainer
var _pending := false
var _name: LineEdit
var _zip_out: FileDialog
var _zip_in: FileDialog


func _ready() -> void:
	name = "Library"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := UiKit.margin(_box, 4)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(m)
	_zip_out = _dialog(FileDialog.FILE_MODE_SAVE_FILE, func(p):
		var path: String = p if p.get_extension() != "" else p + ".zip"
		App.status.emit("Library exported" if Library.export_zip(path) == OK else "Could not write " + path))
	_zip_in = _dialog(FileDialog.FILE_MODE_OPEN_FILE, func(p):
		var n := Library.import_zip(p)
		App.status.emit("Imported %d library items" % n if n >= 0 else "Not a library zip")
		_queue())
	App.active_layer_changed.connect(_queue)
	App.document_changed.connect(_queue)
	_queue()


func _dialog(mode: int, cb: Callable) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = mode
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.zip ; Tessera library"])
	d.file_selected.connect(cb)
	add_child(d)
	return d


func _queue() -> void:
	if not _pending:
		_pending = true
		_build.call_deferred()


func _row(label: String, apply: Callable, remove := Callable()) -> Control:
	var h := HBoxContainer.new()
	var b := UiKit.button(label, apply)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(b)
	if remove.is_valid():
		h.add_child(UiKit.button("✕", remove, "Delete from library"))
	return h


func _preset_name() -> String:
	var t := _name.text.strip_edges()
	return t if t != "" else "Preset %d" % (Time.get_ticks_msec() % 10000)


func _build() -> void:
	_pending = false
	for c in _box.get_children():
		c.queue_free()
	var l := App.active_layer()
	_name = LineEdit.new()
	_name.placeholder_text = "Name for saved presets"
	_box.add_child(_name)
	# Layer presets
	_box.add_child(UiKit.header("Layer presets (apply to the selected layer)"))
	var pixel := l != null and not l.is_direction()
	var flow := HFlowContainer.new()
	for pr in Library.builtin_layer_presets():
		var p: Dictionary = pr
		flow.add_child(UiKit.button(p.name, func():
			if pixel:
				Library.apply_layer_preset(App.active_layer(), p)))
	_box.add_child(flow)
	var ul := Library.items("layer")
	for i in ul.size():
		var idx := i
		_box.add_child(_row("★ " + str(ul[i].name), func():
			if pixel:
				Library.apply_layer_preset(App.active_layer(), Library.items("layer")[idx]),
			func():
				Library.remove("layer", idx)
				_queue()))
	_box.add_child(UiKit.button("Save selected layer as preset", func():
		if pixel:
			Library.add("layer", Library.layer_preset_from(App.active_layer(), _preset_name()))
			_queue()))
	# Display presets
	_box.add_child(HSeparator.new())
	_box.add_child(UiKit.header("Display presets"))
	var dflow := HFlowContainer.new()
	for pn in DisplayStack.PRESETS:
		var pname: String = pn
		dflow.add_child(UiKit.button(pname, func():
			var pr: Dictionary = DisplayStack.PRESETS[pname]
			var al := App.active_layer()
			App.perform("Display preset: " + pname, func():
				var d := DisplayStack.DEFAULTS.duplicate()
				d.merge(pr.display, true)
				App.project.display = d
				if al and not al.is_direction():
					for k in pr.crt:
						al.settings[k] = pr.crt[k])))
	_box.add_child(dflow)
	var ud := Library.items("display")
	for i in ud.size():
		var idx := i
		_box.add_child(_row("★ " + str(ud[i].name), func():
			App.perform("Display preset", func(): App.project.display = Library.items("display")[idx].display.duplicate(true)),
			func():
				Library.remove("display", idx)
				_queue()))
	_box.add_child(UiKit.button("Save current Display stack", func():
		Library.add("display", {"name": _preset_name(), "display": App.project.display.duplicate(true)})
		_queue()))
	# Direction presets
	_box.add_child(HSeparator.new())
	_box.add_child(UiKit.header("Direction presets (selected direction layer)"))
	var is_dir := l != null and l.is_direction()
	var fl := HFlowContainer.new()
	for pn in DirStroke.PRESETS:
		var pname2: String = pn
		fl.add_child(UiKit.button(pname2, func(): _apply_direction({"name": pname2})))
	_box.add_child(fl)
	var udir := Library.items("direction")
	for i in udir.size():
		var idx := i
		_box.add_child(_row("★ " + str(udir[i].name), func(): _apply_direction(Library.items("direction")[idx]),
			func():
				Library.remove("direction", idx)
				_queue()))
	_box.add_child(UiKit.button("Save selected direction layer's strokes", func():
		if is_dir:
			Library.add("direction", Library.direction_preset_from(App.active_layer(), _preset_name()))
			_queue()))
	# Full stack
	_box.add_child(HSeparator.new())
	_box.add_child(UiKit.header("Full-stack presets (all layers' settings + Display)"))
	var us := Library.items("stack")
	for i in us.size():
		var idx := i
		_box.add_child(_row("★ " + str(us[i].name), func(): Library.apply_stack_preset(Library.items("stack")[idx]),
			func():
				Library.remove("stack", idx)
				_queue()))
	_box.add_child(UiKit.button("Save the whole stack", func():
		Library.add("stack", Library.stack_preset_from(_preset_name()))
		_queue()))
	# Shapes
	_box.add_child(HSeparator.new())
	_box.add_child(UiKit.header("Shapes in the library"))
	var ush := Library.items("shapes")
	for i in ush.size():
		var idx := i
		_box.add_child(_row("✦ " + str(ush[i].name) + "  → add to project", func():
			var sh := Shape.from_json(Library.items("shapes")[idx])
			App.perform("Add library shape", func():
				App.project.shapes[sh.id] = sh
				App.project.register_shapes()),
			func():
				Library.remove("shapes", idx)
				_queue()))
	_box.add_child(UiKit.button("Save all project shapes to the library", func():
		var have: Array = Library.items("shapes").map(func(x): return str(x.get("id", "")))
		for id in App.project.shapes:
			if not have.has(str(id)):
				Library.add("shapes", Shape.to_json(App.project.shapes[id]))
		_queue()))
	_box.add_child(HSeparator.new())
	_box.add_child(UiKit.label("Library folder: " + ProjectSettings.globalize_path(Library.DIR), true))
	_box.add_child(UiKit.hbox([
		UiKit.button("Export library…", func(): _zip_out.popup_centered_ratio(0.6)),
		UiKit.button("Import library…", func(): _zip_in.popup_centered_ratio(0.6)),
	]))


func _apply_direction(preset: Dictionary) -> void:
	var l := App.active_layer()
	if l == null or not l.is_direction():
		App.status.emit("Select a direction layer first")
		return
	App.perform("Direction preset: " + str(preset.name), func():
		var arr := l.strokes_at(App.frame)
		arr.clear()
		arr.append_array(Library.direction_strokes(preset)))
