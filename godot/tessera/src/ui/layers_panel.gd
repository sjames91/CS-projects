class_name LayersPanel
extends VBoxContainer
## Layer stack (top of the list = top of the image).

var _list: VBoxContainer
var _props: VBoxContainer
var _rebuild_pending := false


func _ready() -> void:
	name = "Layers"
	var bar := HBoxContainer.new()
	bar.add_child(UiKit.button("+", _add_pixel, "New pixel layer"))
	bar.add_child(UiKit.button("+ Dir", _add_direction, "New direction layer (arrows/curves that other layers can follow)"))
	bar.add_child(UiKit.button("Dup", _duplicate, "Duplicate layer"))
	bar.add_child(UiKit.button("Del", _delete, "Delete layer"))
	bar.add_child(UiKit.button("▲", func(): _move(1), "Move up"))
	bar.add_child(UiKit.button("▼", func(): _move(-1), "Move down"))
	add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_child(scroll)
	_props = VBoxContainer.new()
	add_child(_props)
	for s in [App.document_changed, App.layers_changed, App.active_layer_changed]:
		s.connect(_queue)
	_queue()


func _queue() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	for c in _list.get_children():
		c.queue_free()
	var layers := App.project.layers
	for i in range(layers.size() - 1, -1, -1):
		_list.add_child(_row(layers[i]))
	_build_props()


func _row(l: LayerData) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.35, 0.55) if l.id == App.active_layer_id else Color(0.17, 0.17, 0.2)
	sb.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	panel.add_child(h)
	var vis := _icon_toggle("V", l.visible, "Visible (show / hide)", func(on): _set_meta(l, "visible", on, "Toggle visibility"))
	h.add_child(vis)
	h.add_child(_icon_toggle("S", l.solo, "Solo (view this layer alone)", func(on): _set_meta(l, "solo", on, "Solo")))
	h.add_child(_icon_toggle("L", l.locked, "Lock", func(on): _set_meta(l, "locked", on, "Lock layer")))
	var name_btn := Button.new()
	name_btn.text = ("↝ " if l.is_direction() else "") + l.name + ("  [static]" if l.is_static and not l.is_direction() else "")
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.flat = true
	name_btn.focus_mode = Control.FOCUS_NONE
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.clip_text = true
	name_btn.tooltip_text = "%s · %s · double-click to rename" % [l.name, TilingRegistry.display_name(l.tiling_id)] if not l.is_direction() else "Direction layer"
	name_btn.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if e.double_click:
				_rename(l, name_btn)
			else:
				App.set_active_layer(l.id))
	h.add_child(name_btn)
	return panel


func _icon_toggle(text: String, on: bool, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 0)
	b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.35)
	b.toggled.connect(cb)
	return b


func _set_meta(l: LayerData, key: String, value: Variant, action: String) -> void:
	var lid := l.id
	App.perform(action, func(): App.project.layer_by_id(lid).set(key, value))


func _rename(l: LayerData, anchor: Control) -> void:
	var le := LineEdit.new()
	le.text = l.name
	le.select_all_on_focus = true
	var parent := anchor.get_parent()
	parent.add_child(le)
	parent.move_child(le, anchor.get_index())
	anchor.visible = false
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.grab_focus()
	var done := func(_t = null):
		if not is_instance_valid(le):
			return
		var txt := le.text.strip_edges()
		le.queue_free()
		if txt != "" and txt != l.name:
			_set_meta(l, "name", txt, "Rename layer")
		else:
			anchor.visible = true
	le.text_submitted.connect(done)
	le.focus_exited.connect(done)


func _build_props() -> void:
	for c in _props.get_children():
		c.queue_free()
	var l := App.active_layer()
	if l == null:
		return
	_props.add_child(HSeparator.new())
	var lid := l.id
	_props.add_child(UiKit.slider_row("Opacity", 0, 1, 0.01, l.opacity,
		func(v):
			App.project.layer_by_id(lid).opacity = v
			App.layer_settings_changed.emit(lid),
		func(): App.begin_change(),
		func(): App.end_change("Layer opacity")))
	if not l.is_direction():
		var blend := UiKit.option(LayerData.BLEND_NAMES, l.blend_mode, func(i): _set_meta(l, "blend_mode", i, "Blend mode"))
		_props.add_child(UiKit.hbox([UiKit.label("Blend"), blend]))
		_props.add_child(UiKit.toggle("Static (same content on every frame)", l.is_static, func(on): _set_static(l, on)))


func _set_static(l: LayerData, on: bool) -> void:
	var lid := l.id
	App.perform("Static layer", func():
		var layer := App.project.layer_by_id(lid)
		layer.is_static = on
		if on:
			var keep: PackedByteArray = layer.frames[layer.frame_index(App.frame)] if not layer.frames.is_empty() else PackedByteArray()
			var only: Array[PackedByteArray] = [keep]
			layer.frames = only
		else:
			var base := layer.frames[0]
			var fr: Array[PackedByteArray] = []
			for i in App.project.frame_count:
				fr.append(base.duplicate())
			layer.frames = fr
	, [lid])


func _add_pixel() -> void:
	App.perform("Add layer", func():
		var at := App.project.layer_index(App.active_layer_id) + 1
		var l := App.project.add_layer("Layer %d" % App.project.next_layer_id, "pixel", at)
		App.active_layer_id = l.id)


func _add_direction() -> void:
	App.perform("Add direction layer", func():
		var at := App.project.layer_index(App.active_layer_id) + 1
		var l := App.project.add_layer("Direction %d" % App.project.next_layer_id, "direction", at)
		App.active_layer_id = l.id)


func _duplicate() -> void:
	var src := App.active_layer()
	if src == null:
		return
	App.perform("Duplicate layer", func():
		var l := src.duplicate_layer(App.project.next_layer_id)
		App.project.next_layer_id += 1
		App.project.layers.insert(App.project.layer_index(src.id) + 1, l)
		App.active_layer_id = l.id)


func _delete() -> void:
	if App.project.layers.size() <= 1:
		App.status.emit("Can't delete the last layer")
		return
	var idx := App.project.layer_index(App.active_layer_id)
	App.perform("Delete layer", func():
		App.project.layers.remove_at(idx)
		App.active_layer_id = App.project.layers[clampi(idx - 1, 0, App.project.layers.size() - 1)].id)


func _move(dir: int) -> void:
	var idx := App.project.layer_index(App.active_layer_id)
	var to := idx + dir
	if idx < 0 or to < 0 or to >= App.project.layers.size():
		return
	App.perform("Reorder layers", func():
		var l: LayerData = App.project.layers[idx]
		App.project.layers.remove_at(idx)
		App.project.layers.insert(to, l))
