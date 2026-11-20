class_name RenderHub
extends Node
## Owns the GPU-side resources shared by every view: one cell texture per
## layer frame, the palette texture, and the flattened cache image of every
## non-selected layer. Caches rebuild only when a layer's cells, settings,
## the palette, or the canvas change, one per frame, in an offscreen viewport.

signal caches_updated
signal busy_changed(busy: bool)

var palette_tex: ImageTexture
var _cells_tex := {}    # "lid:fi" -> ImageTexture
var _cells_dirty := {}  # "lid:fi" -> true
var _cache := {}        # "lid:fi" -> ImageTexture
var _cache_valid := {}  # "lid:fi" -> true
var _queue: Array = []  # [lid, frame]
var _rendering := false
var _vp: SubViewport
var _rect: ColorRect
var _flow := {}  # direction layer id -> {key, tex}
var _pat := {}   # "lid:slot:fi" -> {key, tex}
var _rd := {}    # "lid:slot" -> {key, img, tex}
var _blank_rf: ImageTexture
var _mask_src := PackedByteArray()
var _mask_tex: ImageTexture
var _last_active := -1


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.disable_3d = true
	_vp.size = Vector2i(16, 16)
	add_child(_vp)
	_rect = ColorRect.new()
	_rect.material = ShaderMaterial.new()
	_vp.add_child(_rect)
	App.document_changed.connect(_on_document_changed)
	App.layer_cells_changed.connect(_on_cells_changed)
	App.layer_settings_changed.connect(_on_settings_changed)
	App.palette_changed.connect(_on_palette_changed)
	App.active_layer_changed.connect(_on_active_changed)
	App.frame_changed.connect(_schedule_needed)
	App.layers_changed.connect(_schedule_needed)
	_on_palette_changed()
	_on_document_changed()


func _key(lid: int, fi: int) -> String:
	return "%d:%d" % [lid, fi]


# ---- textures -------------------------------------------------------------

func _on_palette_changed() -> void:
	var img := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	var pal := App.project.palette
	for i in mini(pal.size(), 255):
		img.set_pixel(i, 0, pal[i])
	if palette_tex == null:
		palette_tex = ImageTexture.create_from_image(img)
	else:
		palette_tex.update(img)
	invalidate_all()


func cells_texture(layer: LayerData, frame: int) -> ImageTexture:
	var fi := layer.frame_index(frame)
	var k := _key(layer.id, fi)
	var t := App.tiling_of(layer)
	var data := layer.frames[fi]
	if data.size() != t.cell_count():
		data.resize(t.cell_count())
		layer.frames[fi] = data
	var tex: ImageTexture = _cells_tex.get(k)
	if tex == null or tex.get_width() != t.grid.x or tex.get_height() != t.grid.y:
		tex = ImageTexture.create_from_image(Image.create_from_data(t.grid.x, t.grid.y, false, Image.FORMAT_R8, data))
		_cells_tex[k] = tex
		_cells_dirty.erase(k)
	elif _cells_dirty.has(k):
		tex.update(Image.create_from_data(t.grid.x, t.grid.y, false, Image.FORMAT_R8, data))
		_cells_dirty.erase(k)
	return tex


## Selection mask texture for the overlay.
func mask_texture(mask: PackedByteArray, t: Tiling) -> ImageTexture:
	if _mask_src == mask and _mask_tex != null and _mask_tex.get_width() == t.grid.x and _mask_tex.get_height() == t.grid.y:
		return _mask_tex
	_mask_src = mask.duplicate()
	var data := mask.duplicate()
	data.resize(t.cell_count())
	_mask_tex = ImageTexture.create_from_image(Image.create_from_data(t.grid.x, t.grid.y, false, Image.FORMAT_R8, data))
	return _mask_tex


func configure_material(mat: ShaderMaterial, layer: LayerData, frame: int) -> void:
	var t := App.tiling_of(layer)
	mat.shader = ShaderBuilder.layer_shader(t)
	mat.set_shader_parameter("cells_tex", cells_texture(layer, frame))
	mat.set_shader_parameter("palette_tex", palette_tex)
	mat.set_shader_parameter("ucs", t.cs)
	mat.set_shader_parameter("utp", t.glsl_params())
	mat.set_shader_parameter("grid", t.grid)
	mat.set_shader_parameter("canvas_px", App.project.canvas_px())
	mat.set_shader_parameter("opacity", layer.opacity)
	mat.set_shader_parameter("blend_mode", layer.blend_mode)
	var s := layer.settings
	var flow_tex := _flow_texture(int(s.get("flow_layer", 0)), frame)
	mat.set_shader_parameter("flow_on", flow_tex != null)
	if flow_tex:
		mat.set_shader_parameter("flow_tex", flow_tex)
	mat.set_shader_parameter("cell_style", int(s.get("style", 0)))
	mat.set_shader_parameter("pal_count", maxi(App.project.palette.size(), 1))
	mat.set_shader_parameter("flow_drift", _drift(layer, frame))
	var stex := stamp_texture(str(s.get("stamp_shape", "")))
	mat.set_shader_parameter("stamp_on", stex != null)
	if stex:
		mat.set_shader_parameter("stamp_tex", stex)
	_bind_patterns(mat, layer, frame, t)
	for k in s:
		if k in ["style", "flow_layer", "patterns", "dir", "offset_mode", "offset_amount", "stamp_shape"]:
			continue
		var v = s[k]
		if k == "grout_color":
			v = Color.html(v)
		mat.set_shader_parameter(k, v)


# ---- caches ---------------------------------------------------------------

func cache_scale() -> float:
	var px := App.project.canvas_px()
	return clampf(float(App.max_cache_px) / maxf(px.x, px.y), 0.25, 4.0)


## Cache frame slot: static layers share one cache unless they have animated
## features (drifting flow), which get one cache per frame.
func _cfi(layer: LayerData, frame: int) -> int:
	if layer.setting("flow_animate"):
		return frame
	return layer.frame_index(frame)


func cache_texture(layer: LayerData, frame: int) -> ImageTexture:
	var k := _key(layer.id, _cfi(layer, frame))
	if _cache_valid.has(k):
		return _cache.get(k)
	return null


func invalidate_layer(lid: int, fi := -1) -> void:
	for k in _cache_valid.keys():
		var parts: PackedStringArray = k.split(":")
		if int(parts[0]) == lid and (fi < 0 or int(parts[1]) == fi):
			_cache_valid.erase(k)
	_schedule_needed()


func invalidate_all() -> void:
	_cache_valid.clear()
	_schedule_needed()


func _on_document_changed() -> void:
	for k in _cells_tex.keys():
		_cells_dirty[k] = true
	invalidate_all()


func _on_cells_changed(lid: int) -> void:
	var l := App.project.layer_by_id(lid)
	if l == null:
		return
	for i in l.frames.size():
		_cells_dirty[_key(lid, i)] = true
	# The active layer renders live; its cache is rebuilt when deselected.
	for k in _cache_valid.keys():
		if k.begins_with("%d:" % lid):
			_cache_valid.erase(k)
	if lid != App.active_layer_id:
		_schedule_needed()


func _on_settings_changed(lid: int) -> void:
	var ids := [lid]
	var changed := App.project.layer_by_id(lid)
	if changed and changed.is_direction():
		# Layers that follow this direction layer re-render too.
		for l in App.project.layers:
			if int(l.setting("flow_layer")) == lid:
				ids.append(l.id)
	for k in _cache_valid.keys():
		for id in ids:
			if k.begins_with("%d:" % id):
				_cache_valid.erase(k)
	if lid != App.active_layer_id:
		_schedule_needed()


func _on_active_changed() -> void:
	_last_active = App.active_layer_id
	_schedule_needed()


var _schedule_pending := false


func _schedule_needed() -> void:
	if _schedule_pending:
		return
	_schedule_pending = true
	_rebuild_queue.call_deferred()


func _rebuild_queue() -> void:
	_schedule_pending = false
	_queue.clear()
	for l in App.project.layers:
		if l.is_direction() or l.id == App.active_layer_id or not App.layer_shown(l):
			continue
		var fi := _cfi(l, App.frame)
		if not _cache_valid.has(_key(l.id, fi)):
			_queue.append([l.id, App.frame])
	if not _queue.is_empty() and not _rendering:
		busy_changed.emit(true)


func is_busy() -> bool:
	return _rendering or not _queue.is_empty()


func _process(_dt: float) -> void:
	if _rendering or _queue.is_empty():
		return
	var job: Array = _queue.pop_front()
	var layer := App.project.layer_by_id(job[0])
	if layer == null:
		return
	_render_cache(layer, job[1])


func _render_cache(layer: LayerData, frame: int) -> void:
	_rendering = true
	var px := App.project.canvas_px()
	var size := Vector2i((px * cache_scale()).round())
	size = size.max(Vector2i.ONE)
	_vp.size = size
	_rect.size = Vector2(size)
	var mat := _rect.material as ShaderMaterial
	configure_material(mat, layer, frame)
	mat.set_shader_parameter("output_mode", 1)
	mat.set_shader_parameter("raw_mode", false)
	mat.set_shader_parameter("node_origin", Vector2.ZERO)
	mat.set_shader_parameter("node_size", px)
	mat.set_shader_parameter("tile_mode", false)
	var k := _key(layer.id, _cfi(layer, frame))
	var cells_snapshot := layer.cells(frame).duplicate()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var tex: ImageTexture = _cache.get(k)
	if tex != null and tex.get_size() == Vector2(img.get_size()):
		tex.update(img)
	else:
		_cache[k] = ImageTexture.create_from_image(img)
	# Only mark valid if nothing changed while we were rendering.
	if App.project.layer_by_id(layer.id) == layer and layer.cells(frame) == cells_snapshot:
		_cache_valid[k] = true
	_rendering = false
	caches_updated.emit()
	if _queue.is_empty():
		busy_changed.emit(false)


## Render one layer at an arbitrary resolution right now (export).
func render_layer_image(layer: LayerData, frame: int, size: Vector2i, raw := false) -> Image:
	while _rendering:
		await RenderingServer.frame_post_draw
	_rendering = true
	var px := App.project.canvas_px()
	_vp.size = size
	_rect.size = Vector2(size)
	var mat := _rect.material as ShaderMaterial
	configure_material(mat, layer, frame)
	mat.set_shader_parameter("output_mode", 1)
	mat.set_shader_parameter("raw_mode", raw)
	mat.set_shader_parameter("node_origin", Vector2.ZERO)
	mat.set_shader_parameter("node_size", px)
	mat.set_shader_parameter("tile_mode", false)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	_rendering = false
	return img


## Flow field of a direction layer at a frame, recomputed (GPU) only when
## its strokes, field settings or the canvas change.
func _flow_texture(dir_id: int, frame := -1) -> ImageTexture:
	if dir_id <= 0:
		return null
	var d := App.project.layer_by_id(dir_id)
	if d == null or not d.is_direction():
		return null
	var f := App.frame if frame < 0 else frame
	var strokes := d.strokes_at(f)
	var ds := DirStroke.DEFAULT_SETTINGS.duplicate()
	ds.merge(d.settings.get("dir", {}), true)
	if strokes.is_empty() and not ds.default_on:
		return null
	var px := App.project.canvas_px()
	var key := "%s:%s:%s" % [px, hash(strokes.map(func(st): return DirStroke.to_json(st))), hash(ds)]
	var ck := "%d:%d" % [dir_id, 0 if d.is_static else f]
	var entry: Dictionary = _flow.get(ck, {})
	if entry.get("key", "") == key or (App.in_change() and not entry.is_empty()):
		return entry.tex
	var res := Vector2i(App.project.canvas_cells).clamp(Vector2i.ONE, Vector2i(512, 512))
	var img := Gpu.flow_field(strokes, res, px, float(ds.smoothing) * App.project.cell_size, ds.default_on, float(ds.default_angle))
	var tex := ImageTexture.create_from_image(img)
	_flow[ck] = {"key": key, "tex": tex, "img": img}
	return tex


## CPU copy of the field (for the arrow / streamline overlay and export).
func flow_image(dir_id: int, frame := -1) -> Image:
	var tex := _flow_texture(dir_id, frame)
	if tex == null:
		return null
	var d := App.project.layer_by_id(dir_id)
	var f := App.frame if frame < 0 else frame
	return _flow.get("%d:%d" % [dir_id, 0 if d.is_static else f], {}).get("img")


# ---- patterns -----------------------------------------------------------------

func _blank_tex() -> ImageTexture:
	if _blank_rf == null:
		_blank_rf = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RF))
	return _blank_rf


func _bind_patterns(mat: ShaderMaterial, layer: LayerData, frame: int, t: Tiling) -> void:
	var slots := Patterns.slots(layer)
	var n := mini(slots.size(), Patterns.MAX_SLOTS)
	var flags := PackedInt32Array()
	var srcs := PackedInt32Array()
	var filt := PackedInt32Array()
	var filtered := PackedInt32Array()
	var styles: Array = []
	var v2: Dictionary = {"size": [], "rotation": [], "rounding": [], "gap": [], "jitter": [], "shift": []}
	var vis := PackedFloat32Array()
	var fine := PackedFloat32Array()
	var pa: Array = []
	var pb: Array = []
	filt.resize(32)
	for i in Patterns.MAX_SLOTS:
		var sl: Dictionary = slots[i] if i < n else Patterns.default_slot()
		flags.append(int(sl.drives) if i < n else 0)
		srcs.append(int(sl.source))
		var cols: Array = sl.get("colors", [])
		filtered.append(1 if not cols.is_empty() else 0)
		for cidx in cols:
			var ci := int(cidx)
			if ci >= 0 and ci < 256:
				filt[i * 8 + (ci >> 5)] |= 1 << (ci & 31)
		var st: Array = sl.styles
		styles.append(Vector4(st[0], st[1], st[2], int(sl.style_count)))
		for k in v2:
			v2[k].append(Vector2(sl[k][0], sl[k][1]))
		vis.append(float(sl.visibility))
		fine.append(float(sl.fine_amount) if sl.fine else 0.0)
		pa.append(Patterns.params_a(sl))
		pb.append(Patterns.params_b(sl))
		var tex: Texture2D = _blank_tex()
		var rtex: Texture2D = _blank_tex()
		if i < n:
			var r = _rd_raster(layer, i, sl)
			if r:
				rtex = r.tex
			tex = _pattern_texture(layer, frame, i, sl, t, r.img if r else null)
		mat.set_shader_parameter("pat%d" % i, tex)
		mat.set_shader_parameter("patr%d" % i, rtex)
	mat.set_shader_parameter("pat_count", n)
	mat.set_shader_parameter("pat_flags", flags)
	mat.set_shader_parameter("pat_src", srcs)
	mat.set_shader_parameter("pat_filter", filt)
	mat.set_shader_parameter("pat_filtered", filtered)
	mat.set_shader_parameter("pat_styles", styles)
	mat.set_shader_parameter("pat_size", v2.size)
	mat.set_shader_parameter("pat_rot", v2.rotation)
	mat.set_shader_parameter("pat_round", v2.rounding)
	mat.set_shader_parameter("pat_gap", v2.gap)
	mat.set_shader_parameter("pat_jit", v2.jitter)
	mat.set_shader_parameter("pat_shift", v2.shift)
	mat.set_shader_parameter("pat_vis", vis)
	mat.set_shader_parameter("pat_fine", fine)
	mat.set_shader_parameter("pat_a", pa)
	mat.set_shader_parameter("pat_b", pb)
	mat.set_shader_parameter("pat_view", -1)


## Reaction-diffusion raster for a slot (null for other sources). Heavy: only
## recomputed when its own parameters change, and never mid-drag.
func _rd_raster(layer: LayerData, i: int, sl: Dictionary):
	if int(sl.source) != Patterns.Src.REACTION_DIFFUSION:
		return null
	var px := App.project.canvas_px()
	var flow_img: Image = null
	var aniso := 0.0
	if layer.setting("flow_rd") and int(layer.setting("flow_layer")) > 0:
		flow_img = flow_image(int(layer.setting("flow_layer")))
		aniso = float(layer.setting("flow_strength"))
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [sl.seed, sl.scale, sl.feed, sl.kill, sl.iterations, px, App.project.cell_size, aniso, _flow.get(int(layer.setting("flow_layer")), {}).get("key", "")]
	var k := "%d:%d" % [layer.id, i]
	var e: Dictionary = _rd.get(k, {})
	if e.get("key", "") == key or (App.in_change() and not e.is_empty()):
		return e
	busy_changed.emit(true)
	var img := Patterns.reaction_diffusion(sl, px, App.project.cell_size, flow_img, aniso)
	e = {"key": key, "img": img, "tex": ImageTexture.create_from_image(img)}
	_rd[k] = e
	busy_changed.emit(is_busy())
	return e


func _pattern_texture(layer: LayerData, frame: int, i: int, sl: Dictionary, t: Tiling, raster: Image) -> Texture2D:
	var fi := layer.frame_index(frame)
	var k := "%d:%d:%d" % [layer.id, i, fi]
	var key := JSON.stringify(sl) + t.shader_key() + str(t.glsl_params()) + str(t.grid)
	if raster:
		key += str(_rd.get("%d:%d" % [layer.id, i], {}).get("key", ""))
	if Patterns.uses_cells(sl):
		key += str(hash(layer.frames[fi])) + str(App.project.palette)
	if layer.setting("flow_patterns") and int(layer.setting("flow_layer")) > 0:
		var fid := int(layer.setting("flow_layer"))
		_flow_texture(fid, frame)
		var fl := App.project.layer_by_id(fid)
		var fk := "%d:%d" % [fid, 0 if fl == null or fl.is_static else frame]
		key += "|flow" + str(_flow.get(fk, {}).get("key", "")) + str(layer.setting("flow_strength")) + "|" + str(_drift(layer, frame))
	if layer.is_static and layer.setting("flow_animate"):
		k += ":f%d" % frame
	var e: Dictionary = _pat.get(k, {})
	if e.get("key", "") == key or (App.in_change() and not e.is_empty()):
		return e.tex
	var fimg: Image = null
	var fs := 0.0
	if layer.setting("flow_patterns") and int(layer.setting("flow_layer")) > 0:
		fimg = flow_image(int(layer.setting("flow_layer")), frame)
		fs = float(layer.setting("flow_strength"))
	var img := Patterns.cell_map(sl, t, layer.frames[fi], App.project.palette, raster, fimg, fs, _drift(layer, frame))
	var tex: ImageTexture = e.get("tex")
	if tex and tex.get_size() == Vector2(img.get_size()):
		tex.update(img)
	else:
		tex = ImageTexture.create_from_image(img)
	_pat[k] = {"key": key, "tex": tex}
	return tex




## Animated flow: patterns drift along the flow by `speed` pattern units per
## frame. Each frame's maps are computed once (when visited, played or
## exported) and cached.
func _drift(layer: LayerData, frame: int) -> float:
	if not layer.setting("flow_animate"):
		return 0.0
	return float(frame) * float(layer.setting("flow_speed")) * 0.25



var _stamps := {}  # shape id -> {key, tex}


## Stamp shape SDF texture (GPU-baked once per shape edit).
func stamp_texture(shape_id: String) -> ImageTexture:
	if shape_id == "" or not App.project.shapes.has(shape_id):
		return null
	var sh: Dictionary = App.project.shapes[shape_id]
	var key := str(hash(Shape.to_json(sh)))
	var e: Dictionary = _stamps.get(shape_id, {})
	if e.get("key", "") == key:
		return e.tex
	var tex := ImageTexture.create_from_image(Shape.stamp_sdf(sh))
	_stamps[shape_id] = {"key": key, "tex": tex}
	return tex


## Flatten / Apply (explicit user action): bake pattern-driven palette
## shift and visibility into the layer's cells for every frame (GPU), then
## remove those drives so nothing is applied twice. One undo step.
func flatten_patterns(layer: LayerData) -> void:
	var slots := Patterns.slots(layer)
	if slots.is_empty():
		App.status.emit("No patterns to apply")
		return
	App.perform("Flatten / Apply patterns", func():
		var t := App.tiling_of(layer)
		var n := t.cell_count()
		var cfg := PackedFloat32Array()
		var filt := PackedInt32Array()
		filt.resize(Patterns.MAX_SLOTS * 9)
		for i in Patterns.MAX_SLOTS:
			var sl: Dictionary = slots[i] if i < slots.size() else Patterns.default_slot()
			var fl := int(sl.drives) & (Patterns.Drive.PALETTE_SHIFT | Patterns.Drive.VISIBILITY) if i < slots.size() else 0
			cfg.append_array([float(fl), float(sl.shift[0]), float(sl.shift[1]), float(sl.visibility)])
			var cols: Array = sl.get("colors", [])
			filt[i * 9 + 8] = 1 if not cols.is_empty() else 0
			for c in cols:
				filt[i * 9 + (int(c) >> 5)] |= 1 << (int(c) & 31)
		for fi in layer.frames.size():
			var maps := PackedByteArray()
			maps.resize(n * 4 * Patterns.MAX_SLOTS)
			for i in mini(slots.size(), Patterns.MAX_SLOTS):
				var r = _rd_raster(layer, i, slots[i])
				var tex := _pattern_texture(layer, fi, i, slots[i], t, r.img if r else null)
				var d := tex.get_image().get_data()
				# copy slot map into the packed buffer (native slice ops)
				var head := maps.slice(0, i * n * 4)
				var tail := maps.slice((i + 1) * n * 4)
				head.append_array(d.slice(0, n * 4))
				head.append_array(tail)
				maps = head
			layer.frames[fi] = Patterns.flatten(layer.frames[fi], maps, cfg, filt, App.project.palette.size())
		for sl in slots:
			sl.drives = int(sl.drives) & ~(Patterns.Drive.PALETTE_SHIFT | Patterns.Drive.VISIBILITY)
	, [layer.id])
