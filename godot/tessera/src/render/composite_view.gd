class_name CompositeView
extends SubViewport
## Stacks the layers into one image. Non-selected layers come from their
## cache images (canvas space); the selected layer (and any layer whose cache
## is still rebuilding) renders live into its own viewport at view
## resolution. One compositor pass blends up to PER_PASS textures with exact
## straight-alpha maths and every blend mode; more layers chain passes.

const PER_PASS := 16

var hub: RenderHub
var world: Node2D
var show_overlay := false
var frame_override := -1
var raw_only := false          # Render toggle OFF
var tile_mode := false
var onion: Dictionary = {}     # {"before": n, "after": n, "opacity": f}
var texture_override := {}     # lid -> Texture2D (export: pre-rendered layers)

var _zoom := 1.0
var _pan := Vector2.ZERO
var _live := {}                # lid -> {vp, world, rect, mat}
var _passes: Array = []        # intermediate SubViewports
var _rebuild_pending := false
var _blank: ImageTexture
var _pre: SubViewport  # composite before the Display stack
var display_frame := -1.0  # animated display effects; <0 = follow App.frame


func _init() -> void:
	transparent_bg = true
	disable_3d = true
	world = Node2D.new()
	add_child(world)
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_blank = ImageTexture.create_from_image(img)
	size_changed.connect(queue_rebuild)


func setup(h: RenderHub, overlay: bool) -> void:
	hub = h
	show_overlay = overlay
	App.document_changed.connect(queue_rebuild)
	App.layers_changed.connect(queue_rebuild)
	App.layer_settings_changed.connect(func(_l): queue_rebuild())
	App.palette_changed.connect(queue_rebuild)
	App.active_layer_changed.connect(queue_rebuild)
	App.frame_changed.connect(queue_rebuild)
	App.view_changed.connect(queue_rebuild)
	App.selection_changed.connect(queue_rebuild)
	App.layer_cells_changed.connect(_on_cells)
	hub.caches_updated.connect(queue_rebuild)
	queue_rebuild()


func _on_cells(lid: int) -> void:
	# Cell textures update in place; just flush the new bytes to the GPU.
	var l := App.project.layer_by_id(lid)
	if l and not l.is_direction():
		hub.cells_texture(l, current_frame())


func queue_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	rebuild.call_deferred()


func current_frame() -> int:
	return frame_override if frame_override >= 0 else App.frame


func set_view(zoom: float, pan: Vector2) -> void:
	_zoom = zoom
	_pan = pan
	_apply_transform(world)
	for lid in _live:
		_apply_transform(_live[lid].world)
	for p in _passes:
		_apply_transform(p.get_child(0))
	if _pre:
		_apply_transform(_pre.get_child(0))
	_update_display_view()


func _apply_transform(n: Node2D) -> void:
	n.scale = Vector2(_zoom, _zoom)
	n.position = _pan


func _node_rect() -> Rect2:
	var px := App.project.canvas_px()
	if tile_mode:
		return Rect2(-px, px * 3.0)
	return Rect2(Vector2.ZERO, px)


# ---- build ---------------------------------------------------------------------

## Entry: {tex, space (0 canvas, 1 screen), opacity, mode, tint}
func _entries() -> Array:
	var out: Array = []
	var f := current_frame()
	var used_live := {}
	if raw_only:
		var l := App.active_layer()
		if l and not l.is_direction():
			out.append(_live_entry(l, f, true, used_live))
	else:
		for l in App.project.layers:
			if l.is_direction() or not App.layer_shown(l):
				continue
			if not onion.is_empty() and l.id == App.active_layer_id and not l.is_static:
				out.append_array(_onion_entries(l, f))
			if texture_override.has(l.id):
				out.append({"tex": texture_override[l.id], "space": 0, "opacity": l.opacity, "mode": l.blend_mode, "tint": Color.WHITE})
				continue
			var cache: ImageTexture = hub.cache_texture(l, f)
			if l.id == App.active_layer_id or cache == null:
				out.append(_live_entry(l, f, false, used_live))
			else:
				out.append({"tex": cache, "space": 0, "opacity": l.opacity, "mode": l.blend_mode, "tint": Color.WHITE})
	# Drop live viewports that are no longer needed.
	for lid in _live.keys():
		if not used_live.has(lid):
			_live[lid].vp.queue_free()
			_live.erase(lid)
	return out


func _live_entry(l: LayerData, f: int, raw: bool, used: Dictionary) -> Dictionary:
	var r := _node_rect()
	var e: Dictionary = _live.get(l.id, {})
	if e.is_empty():
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		var w := Node2D.new()
		vp.add_child(w)
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		rect.material = mat
		w.add_child(rect)
		add_child(vp)
		e = {"vp": vp, "world": w, "rect": rect, "mat": mat}
		_live[l.id] = e
	used[l.id] = true
	e.vp.size = size
	_apply_transform(e.world)
	e.rect.position = r.position
	e.rect.size = r.size
	var mat: ShaderMaterial = e.mat
	hub.configure_material(mat, l, f)
	mat.set_shader_parameter("output_mode", 1)
	mat.set_shader_parameter("raw_mode", raw)
	mat.set_shader_parameter("node_origin", r.position)
	mat.set_shader_parameter("node_size", r.size)
	mat.set_shader_parameter("tile_mode", tile_mode)
	if show_overlay and l.id == App.active_layer_id:
		mat.set_shader_parameter("pat_view", int(App.pattern_view.get(l.id, -1)))
	return {"tex": e.vp.get_texture(), "space": 1, "opacity": 1.0 if raw else l.opacity,
		"mode": 0 if raw else l.blend_mode, "tint": Color.WHITE}


func _onion_entries(l: LayerData, f: int) -> Array:
	var out: Array = []
	var op: float = onion.get("opacity", 0.3)
	var n_before: int = onion.get("before", 1)
	var n_after: int = onion.get("after", 1)
	for i in range(n_before, 0, -1):
		var tex := hub.cache_texture(l, f - i) if f - i >= 0 else null
		if tex:
			out.append({"tex": tex, "space": 0, "opacity": op / i, "mode": 0, "tint": Color(1.0, 0.55, 0.55)})
	for i in range(n_after, 0, -1):
		var tex := hub.cache_texture(l, f + i) if f + i < App.project.frame_count else null
		if tex:
			out.append({"tex": tex, "space": 0, "opacity": op / i, "mode": 0, "tint": Color(0.55, 1.0, 0.6)})
	return out


func rebuild() -> void:
	_rebuild_pending = false
	if hub == null:
		return
	for c in world.get_children():
		world.remove_child(c)
		c.queue_free()
	for p in _passes:
		p.queue_free()
	_passes.clear()
	var entries := _entries()
	var r := _node_rect()
	# Chain passes of PER_PASS; each pass's output feeds the next as entry 0.
	while entries.size() > PER_PASS:
		var chunk := entries.slice(0, PER_PASS)
		entries = entries.slice(PER_PASS)
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.size = size
		var w := Node2D.new()
		vp.add_child(w)
		_apply_transform(w)
		w.add_child(_compositor(chunk, r))
		add_child(vp)
		_passes.append(vp)
		entries.push_front({"tex": vp.get_texture(), "space": 1, "opacity": 1.0, "mode": 0, "tint": Color.WHITE})
	var use_display := not raw_only and DisplayStack.any_on(App.project)
	if use_display:
		if _pre == null:
			_pre = SubViewport.new()
			_pre.transparent_bg = true
			_pre.disable_3d = true
			_pre.add_child(Node2D.new())
			add_child(_pre)
		_pre.size = size
		var pw: Node2D = _pre.get_child(0)
		for c in pw.get_children():
			c.queue_free()
		_apply_transform(pw)
		pw.add_child(_compositor(entries, r))
		world.add_child(_display_rect(r))
	else:
		if _pre:
			_pre.queue_free()
			_pre = null
		world.add_child(_compositor(entries, r))
	if show_overlay:
		_add_overlay(r)


func _compositor(entries: Array, r: Rect2) -> ColorRect:
	var mat := ShaderMaterial.new()
	mat.shader = ShaderBuilder.compositor_shader(PER_PASS)
	var spaces := PackedInt32Array()
	var modes := PackedInt32Array()
	var ops := PackedFloat32Array()
	var tints := PackedColorArray()
	for i in PER_PASS:
		var e: Dictionary = entries[i] if i < entries.size() else {}
		mat.set_shader_parameter("t%d" % i, e.get("tex", _blank))
		spaces.append(e.get("space", 0))
		modes.append(e.get("mode", 0))
		ops.append(e.get("opacity", 0.0))
		tints.append(e.get("tint", Color.WHITE))
	mat.set_shader_parameter("n", entries.size())
	mat.set_shader_parameter("space", spaces)
	mat.set_shader_parameter("mode", modes)
	mat.set_shader_parameter("op", ops)
	mat.set_shader_parameter("tint", tints)
	mat.set_shader_parameter("canvas_px", App.project.canvas_px())
	mat.set_shader_parameter("node_origin", r.position)
	mat.set_shader_parameter("node_size", r.size)
	mat.set_shader_parameter("tile_mode", tile_mode)
	var rect := ColorRect.new()
	rect.material = mat
	rect.position = r.position
	rect.size = r.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _add_overlay(r: Rect2) -> void:
	var l := App.active_layer()
	if l == null or l.is_direction():
		return
	var t := App.tiling_of(l)
	var mat := ShaderMaterial.new()
	mat.shader = ShaderBuilder.overlay_shader(t)
	mat.set_shader_parameter("ucs", t.cs)
	mat.set_shader_parameter("utp", t.glsl_params())
	mat.set_shader_parameter("grid", t.grid)
	mat.set_shader_parameter("grid_on", App.grid_on)
	mat.set_shader_parameter("canvas_px", App.project.canvas_px())
	mat.set_shader_parameter("node_origin", r.position)
	mat.set_shader_parameter("node_size", r.size)
	mat.set_shader_parameter("tile_mode", tile_mode)
	var has_sel := App.has_selection()
	mat.set_shader_parameter("has_sel", has_sel)
	if has_sel:
		mat.set_shader_parameter("sel_tex", hub.mask_texture(App.selection, t))
	var rect := ColorRect.new()
	rect.material = mat
	rect.position = r.position
	rect.size = r.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(rect)


var _display_mat: ShaderMaterial


func _display_rect(r: Rect2) -> ColorRect:
	_display_mat = ShaderMaterial.new()
	_display_mat.shader = DisplayStack.shader()
	var d := DisplayStack.settings(App.project)
	for k in d:
		_display_mat.set_shader_parameter(k, d[k])
	_display_mat.set_shader_parameter("pre_tex", _pre.get_texture())
	_display_mat.set_shader_parameter("canvas_px", App.project.canvas_px())
	_display_mat.set_shader_parameter("node_origin", r.position)
	_display_mat.set_shader_parameter("node_size", r.size)
	_display_mat.set_shader_parameter("tile_mode", tile_mode)
	_update_display_view()
	var rect := ColorRect.new()
	rect.material = _display_mat
	rect.position = r.position
	rect.size = r.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _update_display_view() -> void:
	if _display_mat == null:
		return
	_display_mat.set_shader_parameter("view_size", Vector2(size))
	_display_mat.set_shader_parameter("zoom", _zoom)
	_display_mat.set_shader_parameter("pan", _pan)
	_display_mat.set_shader_parameter("frame", display_frame if display_frame >= 0.0 else float(App.anim_tick))
