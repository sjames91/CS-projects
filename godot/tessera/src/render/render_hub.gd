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
	var flow_tex := _flow_texture(int(s.get("flow_layer", 0)))
	mat.set_shader_parameter("flow_on", flow_tex != null)
	if flow_tex:
		mat.set_shader_parameter("flow_tex", flow_tex)
	mat.set_shader_parameter("cell_style", int(s.get("style", 0)))
	for k in s:
		if k == "style" or k == "flow_layer":
			continue
		var v = s[k]
		if k == "grout_color":
			v = Color.html(v)
		mat.set_shader_parameter(k, v)


# ---- caches ---------------------------------------------------------------

func cache_scale() -> float:
	var px := App.project.canvas_px()
	return clampf(float(App.max_cache_px) / maxf(px.x, px.y), 0.25, 4.0)


func cache_texture(layer: LayerData, frame: int) -> ImageTexture:
	var k := _key(layer.id, layer.frame_index(frame))
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
	for k in _cache_valid.keys():
		if k.begins_with("%d:" % lid):
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
		var fi := l.frame_index(App.frame)
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
	var k := _key(layer.id, layer.frame_index(frame))
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
func render_layer_image(layer: LayerData, frame: int, size: Vector2i) -> Image:
	while _rendering:
		await RenderingServer.frame_post_draw
	_rendering = true
	var px := App.project.canvas_px()
	_vp.size = size
	_rect.size = Vector2(size)
	var mat := _rect.material as ShaderMaterial
	configure_material(mat, layer, frame)
	mat.set_shader_parameter("output_mode", 1)
	mat.set_shader_parameter("raw_mode", false)
	mat.set_shader_parameter("node_origin", Vector2.ZERO)
	mat.set_shader_parameter("node_size", px)
	mat.set_shader_parameter("tile_mode", false)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	_rendering = false
	return img


## Flow field of a direction layer, recomputed (GPU) only when its strokes
## or the canvas change.
func _flow_texture(dir_id: int) -> ImageTexture:
	if dir_id <= 0:
		return null
	var d := App.project.layer_by_id(dir_id)
	if d == null or not d.is_direction() or d.strokes.is_empty():
		return null
	var px := App.project.canvas_px()
	var key := str(px) + ":" + str(d.strokes.hash())
	var entry: Dictionary = _flow.get(dir_id, {})
	if entry.get("key", "") == key:
		return entry.tex
	var res := Vector2i(App.project.canvas_cells).clamp(Vector2i.ONE, Vector2i(512, 512))
	var img := Gpu.flow_field(d.strokes, res, px)
	var tex := ImageTexture.create_from_image(img)
	_flow[dir_id] = {"key": key, "tex": tex}
	return tex
