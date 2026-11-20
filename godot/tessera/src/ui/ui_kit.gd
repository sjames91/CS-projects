class_name UiKit
extends RefCounted
## Small builders so every panel's controls look and behave the same.
## Slider rows give one undo step per complete drag via the callbacks.


static func label(text: String, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	if dim:
		l.modulate = Color(1, 1, 1, 0.6)
	return l


static func header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
	return l


static func button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


static func toggle(text: String, on: bool, cb: Callable, tip := "") -> CheckBox:
	var b := CheckBox.new()
	b.text = text
	b.button_pressed = on
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(cb)
	return b


static func option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.select(clampi(selected, 0, items.size() - 1))
	o.focus_mode = Control.FOCUS_NONE
	o.item_selected.connect(cb)
	return o


## Label + slider + numeric field. on_change(value) fires live;
## on_begin() / on_end() bracket a complete drag (or one click / typed value).
static func slider_row(text: String, minv: float, maxv: float, step: float, value: float,
		on_change: Callable, on_begin: Callable, on_end: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 96
	l.clip_text = true
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.step = step
	sb.value = value
	sb.custom_minimum_size.x = 74
	sb.select_all_on_focus = true
	row.add_child(sb)
	var state := {"dragging": false, "sync": false}
	s.drag_started.connect(func():
		state.dragging = true
		on_begin.call())
	s.drag_ended.connect(func(_changed):
		state.dragging = false
		on_end.call())
	s.value_changed.connect(func(v):
		if state.sync:
			return
		state.sync = true
		sb.value = v
		state.sync = false
		if state.dragging:
			on_change.call(v)
		else:
			on_begin.call()
			on_change.call(v)
			on_end.call())
	sb.value_changed.connect(func(v):
		if state.sync:
			return
		state.sync = true
		s.value = v
		state.sync = false
		on_begin.call()
		on_change.call(v)
		on_end.call())
	return row


static func color_button(c: Color, cb: Callable) -> ColorPickerButton:
	var b := ColorPickerButton.new()
	b.color = c
	b.custom_minimum_size = Vector2(40, 22)
	b.edit_alpha = false
	b.focus_mode = Control.FOCUS_NONE
	b.color_changed.connect(cb)
	return b


static func hbox(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	for c in children:
		h.add_child(c)
	return h


static func margin(c: Control, px := 6) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.add_child(c)
	return m
