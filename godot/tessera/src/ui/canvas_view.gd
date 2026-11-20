class_name CanvasView
extends Control
## Main canvas. Artwork comes from a CompositeView; grid lines and the
## selection outline are an overlay shader inside it; cursor, marquees,
## lasso and direction arrows are drawn here in screen space.

signal view_moved

var hub: RenderHub
var view: CompositeView
var container: SubViewportContainer
var overlay: Control
var tools := ToolController.new()
var zoom := 8.0
var pan := Vector2(40, 40)
var _panning := false
var _pan_from := Vector2.ZERO
var _space_down := false
var _hover := Vector2(-1e9, -1e9)
var _fitted := false


func setup(h: RenderHub) -> void:
	hub = h
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	container = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	view = CompositeView.new()
	container.add_child(view)
	view.setup(hub, true)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	App.view_changed.connect(_on_view_settings)
	App.document_changed.connect(func(): overlay.queue_redraw(); queue_redraw())
	App.layers_changed.connect(overlay.queue_redraw)
	App.active_layer_changed.connect(overlay.queue_redraw)
	resized.connect(_on_resized)
	_on_view_settings()


func _on_resized() -> void:
	if not _fitted and size.x > 10:
		_fitted = true
		fit_view()
	_apply_view()


func _on_view_settings() -> void:
	view.raw_only = not App.render_on
	view.tile_mode = App.tile_preview
	view.queue_rebuild()
	queue_redraw()
	overlay.queue_redraw()


func set_onion(o: Dictionary) -> void:
	view.onion = o
	view.queue_rebuild()


# ---- view transform ----------------------------------------------------------

func canvas_to_screen(p: Vector2) -> Vector2:
	return p * zoom + pan


func screen_to_canvas(s: Vector2) -> Vector2:
	return (s - pan) / zoom


func fit_view() -> void:
	var px := App.project.canvas_px()
	if App.tile_preview:
		px *= 3.0
	zoom = clampf(minf(size.x / px.x, size.y / px.y) * 0.9, 0.05, 256.0)
	var off := App.project.canvas_px() if App.tile_preview else Vector2.ZERO
	pan = (size - px * zoom) * 0.5 + off * zoom
	_apply_view()


func center_on(canvas_point: Vector2) -> void:
	pan = size * 0.5 - canvas_point * zoom
	_apply_view()


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_canvas(screen_pos)
	zoom = clampf(zoom * factor, 0.05, 256.0)
	pan = screen_pos - before * zoom
	_apply_view()


func _apply_view() -> void:
	if view:
		view.set_view(zoom, pan)
	queue_redraw()
	if overlay:
		overlay.queue_redraw()
	view_moved.emit()


## Visible canvas rect (canvas px), for the preview's view box.
func visible_canvas_rect() -> Rect2:
	return Rect2(screen_to_canvas(Vector2.ZERO), size / zoom)


# ---- input ---------------------------------------------------------------

func _mods(e: InputEventWithModifiers) -> Dictionary:
	return {"shift": e.shift_pressed, "ctrl": e.ctrl_pressed or e.meta_pressed, "alt": e.alt_pressed}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(mb.position, 1.15)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(mb.position, 1.0 / 1.15)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and _space_down):
			_panning = mb.pressed
			_pan_from = mb.position
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			grab_focus()
			var p := screen_to_canvas(mb.position)
			if mb.pressed:
				if tools.active:
					tools.cancel()  # pressing the other button cancels the stroke
				else:
					tools.press(p, mb.button_index == MOUSE_BUTTON_RIGHT, _mods(mb))
			else:
				tools.release(p, _mods(mb))
			overlay.queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			pan += mm.position - _pan_from
			_pan_from = mm.position
			_apply_view()
		_hover = screen_to_canvas(mm.position)
		App.hover_canvas_point = _hover
		if tools.active:
			tools.drag(_hover, _mods(mm))
		overlay.queue_redraw()
	elif event is InputEventMagnifyGesture:
		zoom_at((event as InputEventMagnifyGesture).position, (event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		pan -= (event as InputEventPanGesture).delta * 8.0
		_apply_view()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE:
		_space_down = event.pressed
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE and tools.active:
		tools.cancel()
		overlay.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2(-1e9, -1e9)
		App.hover_canvas_point = _hover
		overlay.queue_redraw()


# ---- drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12))
	var px := App.project.canvas_px()
	var r := Rect2(canvas_to_screen(Vector2.ZERO), px * zoom)
	if App.tile_preview:
		r = Rect2(canvas_to_screen(-px), px * 3.0 * zoom)
	# Checkerboard behind the transparent canvas.
	var vis := r.intersection(Rect2(Vector2.ZERO, size))
	if vis.size.x <= 0:
		return
	draw_rect(vis, Color(0.32, 0.32, 0.35))
	var step := 12.0
	var y0 := floorf(vis.position.y / step) * step
	var x0 := floorf(vis.position.x / step) * step
	var y := y0
	while y < vis.end.y:
		var x := x0 + (fmod(y / step, 2.0) * step)
		while x < vis.end.x:
			var cell := Rect2(x, y, step, step).intersection(vis)
			if cell.size.x > 0 and cell.size.y > 0:
				draw_rect(cell, Color(0.4, 0.4, 0.43))
			x += step * 2.0
		y += step


func _draw_overlay() -> void:
	var px := App.project.canvas_px()
	overlay.draw_rect(Rect2(canvas_to_screen(Vector2.ZERO), px * zoom), Color(1, 1, 1, 0.35), false, 1.0)
	var layer := App.active_layer()
	if layer == null:
		return
	# Direction layers: arrows always visible as UI (only on this canvas).
	for l in App.project.layers:
		if l.is_direction() and (App.layer_shown(l) or l.id == App.active_layer_id):
			var col := Color(1.0, 0.85, 0.2, 0.95 if l.id == App.active_layer_id else 0.45)
			for s in l.strokes:
				_draw_arrow_stroke(s, col)
	if layer.is_direction():
		var st := tools.pending_stroke()
		if st.size() > 1:
			_draw_arrow_stroke(st, Color(1, 1, 1, 0.9))
		if _hover.x > -1e8:
			overlay.draw_arc(canvas_to_screen(_hover), App.project.cell_size * zoom * 0.5, 0, TAU, 24, Color(1, 0.85, 0.2, 0.8), 1.0)
		return
	var t := App.tiling_of(layer)
	# Hovered cell (+ mirrors).
	if _hover.x > -1e8 and not tools.active or (tools.active and tools._tool in ["pencil", "eraser"]):
		var hp := _hover
		var shift := Vector2.ZERO
		if App.wrap_draw or App.tile_preview:
			var w := Vector2(fposmod(hp.x, px.x), fposmod(hp.y, px.y))
			shift = hp - w
			hp = w
		for m in tools._mirrors():
			var c := t.point_to_cell(m * hp)
			if t.in_grid(c):
				var poly := t.cell_polygon(c)
				var sp := PackedVector2Array()
				for v in poly:
					sp.append(canvas_to_screen(v + (shift if m == Transform2D.IDENTITY else Vector2.ZERO)))
				sp.append(sp[0])
				overlay.draw_polyline(sp, Color(1, 1, 1, 0.9), 1.5)
				overlay.draw_polyline(sp, Color(0, 0, 0, 0.5), 0.5)
	# Mirror axes.
	if App.mirror in [1, 3]:
		overlay.draw_line(canvas_to_screen(Vector2(px.x * 0.5, 0)), canvas_to_screen(Vector2(px.x * 0.5, px.y)), Color(0.4, 0.8, 1, 0.5), 1.0)
	if App.mirror in [2, 3]:
		overlay.draw_line(canvas_to_screen(Vector2(0, px.y * 0.5)), canvas_to_screen(Vector2(px.x, px.y * 0.5)), Color(0.4, 0.8, 1, 0.5), 1.0)
	if tools.active:
		match tools._tool:
			"select_rect":
				var r := Rect2(tools.start, Vector2.ZERO).expand(tools.current)
				overlay.draw_rect(Rect2(canvas_to_screen(r.position), r.size * zoom), Color(1, 1, 1, 0.9), false, 1.0)
			"lasso":
				if tools.lasso.size() > 1:
					var sp := PackedVector2Array()
					for v in tools.lasso:
						sp.append(canvas_to_screen(v))
					overlay.draw_polyline(sp, Color(1, 1, 1, 0.9), 1.0)
			"rect", "ellipse":
				var r := tools.shape_rect()
				overlay.draw_rect(Rect2(canvas_to_screen(r.position), r.size * zoom), Color(1, 1, 1, 0.25), false, 1.0)


func _draw_arrow_stroke(s: PackedVector2Array, col: Color) -> void:
	if s.size() < 2:
		return
	var sp := PackedVector2Array()
	for v in s:
		sp.append(canvas_to_screen(v))
	overlay.draw_polyline(sp, Color(0, 0, 0, col.a * 0.6), 4.0)
	overlay.draw_polyline(sp, col, 2.0)
	# Arrowheads along the stroke and at its end.
	var acc := 0.0
	var spacing := 60.0
	for i in range(1, sp.size()):
		var seg := sp[i] - sp[i - 1]
		acc += seg.length()
		if acc >= spacing or i == sp.size() - 1:
			acc = 0.0
			var dir := seg.normalized()
			var tip := sp[i]
			var a := tip - dir * 9.0 + dir.orthogonal() * 5.0
			var b := tip - dir * 9.0 - dir.orthogonal() * 5.0
			overlay.draw_colored_polygon(PackedVector2Array([tip, a, b]), col)
