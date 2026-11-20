class_name TimelinePanel
extends VBoxContainer
## Frames, playback and onion skin. Every non-static layer has its own
## content per frame.

signal onion_changed(settings: Dictionary)

var playing := false
var mode := 0  # 0 loop, 1 ping-pong, 2 once
var _dir := 1
var _acc := 0.0
var _frames: HBoxContainer
var _play_btn: Button
var _dur: SpinBox
var _fps: SpinBox
var _onion := {"on": false, "before": 1, "after": 1, "opacity": 0.35}
var _pending := false


func _ready() -> void:
	var bar := HBoxContainer.new()
	bar.add_child(UiKit.label("Frames"))
	bar.add_child(UiKit.button("+", _add, "Add blank frame after this one"))
	bar.add_child(UiKit.button("Dup", _dup, "Duplicate frame"))
	bar.add_child(UiKit.button("Del", _del, "Delete frame"))
	bar.add_child(UiKit.button("◀", func(): _move(-1), "Move frame earlier"))
	bar.add_child(UiKit.button("▶", func(): _move(1), "Move frame later"))
	bar.add_child(VSeparator.new())
	bar.add_child(UiKit.button("⏮", func(): step(-1), "Step back (,)"))
	_play_btn = UiKit.button("▶ Play", toggle_play, "Play / pause (Enter)")
	bar.add_child(_play_btn)
	bar.add_child(UiKit.button("⏭", func(): step(1), "Step forward (.)"))
	bar.add_child(UiKit.option(["Loop", "Ping-pong", "Once"], 0, func(i): mode = i))
	bar.add_child(UiKit.label("FPS"))
	_fps = SpinBox.new()
	_fps.min_value = 1
	_fps.max_value = 60
	_fps.value = App.project.fps
	_fps.value_changed.connect(func(v):
		if int(v) != App.project.fps:
			App.perform("FPS", func(): App.project.fps = int(v)))
	bar.add_child(_fps)
	bar.add_child(UiKit.label("Frame ms"))
	_dur = SpinBox.new()
	_dur.min_value = 0
	_dur.max_value = 10000
	_dur.step = 10
	_dur.tooltip_text = "This frame's duration in ms (0 = use FPS)"
	_dur.value_changed.connect(func(v):
		var f := App.frame
		if f < App.project.frame_durations.size() and int(v) != App.project.frame_durations[f]:
			App.perform("Frame duration", func(): App.project.frame_durations[f] = int(v)))
	bar.add_child(_dur)
	bar.add_child(VSeparator.new())
	bar.add_child(UiKit.toggle("Onion", false, func(on):
		_onion.on = on
		_emit_onion()))
	var ob := SpinBox.new()
	ob.min_value = 0
	ob.max_value = 5
	ob.value = 1
	ob.tooltip_text = "Previous frames shown"
	ob.value_changed.connect(func(v):
		_onion.before = int(v)
		_emit_onion())
	bar.add_child(ob)
	var oa := SpinBox.new()
	oa.min_value = 0
	oa.max_value = 5
	oa.value = 1
	oa.tooltip_text = "Next frames shown"
	oa.value_changed.connect(func(v):
		_onion.after = int(v)
		_emit_onion())
	bar.add_child(oa)
	var oo := HSlider.new()
	oo.min_value = 0.05
	oo.max_value = 1.0
	oo.step = 0.05
	oo.value = 0.35
	oo.custom_minimum_size.x = 70
	oo.tooltip_text = "Onion opacity"
	oo.value_changed.connect(func(v):
		_onion.opacity = v
		_emit_onion())
	bar.add_child(oo)
	add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 34
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frames = HBoxContainer.new()
	scroll.add_child(_frames)
	add_child(scroll)
	for s in [App.document_changed, App.frame_changed]:
		s.connect(_queue)
	_queue()


func _emit_onion() -> void:
	onion_changed.emit({"before": _onion.before, "after": _onion.after, "opacity": _onion.opacity} if _onion.on else {})


func _queue() -> void:
	if not _pending:
		_pending = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_pending = false
	for c in _frames.get_children():
		c.queue_free()
	for i in App.project.frame_count:
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(30, 26)
		b.toggle_mode = true
		b.button_pressed = i == App.frame
		b.focus_mode = Control.FOCUS_NONE
		var fi := i
		b.pressed.connect(func(): App.set_frame(fi))
		_frames.add_child(b)
	_fps.set_value_no_signal(App.project.fps)
	if App.frame < App.project.frame_durations.size():
		_dur.set_value_no_signal(App.project.frame_durations[App.frame])


func _frame_op(action: String, fn: Callable) -> void:
	App.perform(action, func():
		fn.call()
		App.frame = clampi(App.frame, 0, App.project.frame_count - 1)
	, ["all"])


func _add() -> void:
	var at := App.frame + 1
	_frame_op("Add frame", func():
		for l in App.project.layers:
			l.insert_frame(at, -1, App.tiling_of(l).cell_count())
		App.project.frame_count += 1
		App.project.frame_durations.insert(at, 0)
		App.frame = at)


func _dup() -> void:
	var src := App.frame
	_frame_op("Duplicate frame", func():
		for l in App.project.layers:
			l.insert_frame(src + 1, src, 0)
		App.project.frame_count += 1
		App.project.frame_durations.insert(src + 1, App.project.frame_durations[src])
		App.frame = src + 1)


func _del() -> void:
	if App.project.frame_count <= 1:
		return
	var f := App.frame
	_frame_op("Delete frame", func():
		for l in App.project.layers:
			l.remove_frame(f)
		App.project.frame_count -= 1
		App.project.frame_durations.remove_at(f))


func _move(d: int) -> void:
	var f := App.frame
	var to := f + d
	if to < 0 or to >= App.project.frame_count:
		return
	_frame_op("Move frame", func():
		for l in App.project.layers:
			l.swap_frames(f, to)
		var dd := App.project.frame_durations[f]
		App.project.frame_durations[f] = App.project.frame_durations[to]
		App.project.frame_durations[to] = dd
		App.frame = to)


func step(d: int) -> void:
	var n := App.project.frame_count
	App.set_frame(posmod(App.frame + d, n))


func toggle_play() -> void:
	playing = not playing
	_play_btn.text = "⏸ Pause" if playing else "▶ Play"
	_acc = 0.0
	_dir = 1


func _process(dt: float) -> void:
	if not playing:
		return
	if App.project.frame_count <= 1:
		_acc += dt * 1000.0
		if _acc >= App.project.frame_duration_ms(0):
			_acc = 0.0
			App.anim_tick += 1
			App.frame_changed.emit()
		return
	App.anim_tick += 0
	_acc += dt * 1000.0
	var dur := App.project.frame_duration_ms(App.frame)
	if _acc < dur:
		return
	_acc -= dur
	var n := App.project.frame_count
	var f := App.frame + _dir
	if mode == 0:
		f = posmod(f, n)
	elif mode == 1:
		if f >= n or f < 0:
			_dir = -_dir
			f = App.frame + _dir
	else:
		if f >= n:
			toggle_play()
			return
	App.anim_tick += 1
	App.set_frame(clampi(f, 0, n - 1))
