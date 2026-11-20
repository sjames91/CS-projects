class_name LayerData
extends RefCounted
## One layer: its own grid of palette indexes (per frame) plus the
## non-destructive settings that decide how it is drawn.
## Cell byte 0 = empty, n = palette entry n-1.

enum Blend { NORMAL, MULTIPLY, SCREEN, OVERLAY, ADD }
const BLEND_NAMES := ["Normal", "Multiply", "Screen", "Overlay", "Add"]

enum Style { FLAT, DOT, CROSS_STITCH, LED, LITE_BRITE, BRUSH_DAB, MOSAIC, CRT, SVG_STAMP }
const STYLE_NAMES := ["Flat", "Dot", "Cross-stitch X", "LED dot", "Lite-Brite peg", "Brush dab", "Mosaic tile", "CRT phosphor", "SVG stamp"]

const DEFAULT_SETTINGS := {
	"style": 0,
	"dot_size": 0.8,
	"stamp_thickness": 0.3,
	"rounding_on": false,
	"rounding": 0.4,
	"rounding_color_aware": false,
	"rounding_inner": false,
	"gap_on": false,
	"gap": 0.15,
	"grout_on": true,
	"grout_color": "#1a1a1f",
	"boundary_mode": 0,
	"boundary_width": 0.5,
	"jitter_on": false,
	"jitter_source": 0,
	"jitter_pos": 0.25,
	"jitter_size": 0.2,
	"jitter_rot": 0.2,
	"jitter_seed": 1,
	"flow_layer": 0,
	"offset_mode": 0,
	"patterns": [],
	"stamp_shape": "",
	"flow_strength": 1.0,
	"flow_rd": false,
	"flow_stamp_rot": false,
	"flow_cell_rot": false,
	"flow_patterns": false,
	"flow_animate": false,
	"flow_speed": 1.0,
	"dir": {},
	"offset_amount": 0.5,
	"scan_on": false,
	"scan_thickness": 0.4,
	"scan_dark": 0.5,
	"scan_spacing": 3.0,
	"mask_on": false,
	"mask_type": 0,
	"mask_strength": 0.5,
	"mask_size": 1.0,
	"beam_on": false,
	"beam_amount": 0.6,
	"bleed_on": false,
	"bleed": 0.5,
}

var id: int = 0
var name: String = "Layer"
var kind: String = "pixel"  # "pixel" | "direction"
var visible: bool = true
var locked: bool = false
var solo: bool = false
var opacity: float = 1.0
var blend_mode: int = Blend.NORMAL
var is_static: bool = false
var tiling_id: String = "square"
var tiling_params: Dictionary = {}
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var frames: Array[PackedByteArray] = []
## Direction layer data: one Array of DirStroke dictionaries per frame
## (a single entry when the layer is static).
var stroke_frames: Array = [[]]

## Bumped whenever any custom shape's geometry changes (rebuilds tilings).
static var shape_epoch := 0

var _tiling: Tiling = null
var _tiling_key: String = ""


func is_direction() -> bool:
	return kind == "direction"


func tiling(cell_size: float, canvas_px: Vector2) -> Tiling:
	var mode := int(setting("offset_mode"))
	var amount := float(setting("offset_amount"))
	var key := "%s|%s|%s|%s|%d|%s|%d" % [tiling_id, cell_size, canvas_px, JSON.stringify(tiling_params), mode, amount, shape_epoch]
	if _tiling == null or key != _tiling_key:
		_tiling = LayerData.make_tiling(tiling_id, tiling_params, mode, amount, cell_size, canvas_px)
		_tiling_key = key
	return _tiling


## Base tiling, wrapped by the Offset decorator when an offset is set. With an
## offset the wrapped tiling covers one extra cell so the shifted grid still
## covers the whole canvas.
static func make_tiling(tid: String, tparams: Dictionary, offset_mode: int, amount: float, cell_size: float, canvas_px: Vector2) -> Tiling:
	if offset_mode == 0:
		return TilingRegistry.create(tid, cell_size, canvas_px, tparams)
	var b := TilingRegistry.create(tid, cell_size, canvas_px + Vector2(cell_size, cell_size), tparams)
	return OffsetTiling.wrap(b, cell_size, canvas_px, offset_mode, amount)


func frame_index(frame: int) -> int:
	if is_static or frames.is_empty():
		return 0
	return clampi(frame, 0, frames.size() - 1)


func cells(frame: int) -> PackedByteArray:
	return frames[frame_index(frame)]


func set_cells(frame: int, data: PackedByteArray) -> void:
	frames[frame_index(frame)] = data


func setting(key: String) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func ensure_frames(count: int, cell_count: int) -> void:
	while frames.size() < count:
		var blank := PackedByteArray()
		blank.resize(cell_count)
		frames.append(blank)
	for i in frames.size():
		if frames[i].size() != cell_count:
			frames[i].resize(cell_count)


## Everything except cell data (cheap undo snapshots).
func meta_dict() -> Dictionary:
	return {
		"id": id, "name": name, "kind": kind, "visible": visible, "locked": locked,
		"solo": solo, "opacity": opacity, "blend_mode": blend_mode, "is_static": is_static,
		"tiling_id": tiling_id, "tiling_params": tiling_params.duplicate(true),
		"settings": settings.duplicate(true), "stroke_frames": LayerData.copy_strokes(stroke_frames),
	}


func apply_meta(d: Dictionary) -> void:
	id = d.get("id", id)
	name = d.get("name", name)
	kind = d.get("kind", kind)
	visible = d.get("visible", visible)
	locked = d.get("locked", locked)
	solo = d.get("solo", solo)
	opacity = d.get("opacity", opacity)
	blend_mode = d.get("blend_mode", blend_mode)
	is_static = d.get("is_static", is_static)
	tiling_id = d.get("tiling_id", tiling_id)
	tiling_params = d.get("tiling_params", tiling_params).duplicate(true)
	var s: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	s.merge(d.get("settings", {}), true)
	settings = s
	stroke_frames = LayerData.copy_strokes(d.get("stroke_frames", stroke_frames))


func duplicate_layer(new_id: int) -> LayerData:
	var l := LayerData.new()
	l.apply_meta(meta_dict())
	l.id = new_id
	l.name = name + " copy"
	for f in frames:
		l.frames.append(f.duplicate())
	return l



static func copy_strokes(sf: Array) -> Array:
	var out: Array = []
	for fr in sf:
		var f2: Array = []
		for st in fr:
			var c: Dictionary = st.duplicate()
			c.points = (st.points as PackedVector2Array).duplicate()
			f2.append(c)
		out.append(f2)
	return out


## Strokes of a direction layer at a frame (static layers share one list).
func strokes_at(frame: int) -> Array:
	if stroke_frames.is_empty():
		stroke_frames.append([])
	var i := 0 if is_static else clampi(frame, 0, stroke_frames.size() - 1)
	return stroke_frames[i]


func all_strokes() -> Array:
	var out: Array = []
	for fr in stroke_frames:
		out.append_array(fr)
	return out


# ---- frame operations (cells and direction strokes together) ---------------------

func insert_frame(at: int, copy_from: int, cell_count: int) -> void:
	if is_static:
		return
	if copy_from >= 0:
		frames.insert(at, frames[clampi(copy_from, 0, frames.size() - 1)].duplicate())
		stroke_frames.insert(at, LayerData.copy_strokes([stroke_frames[clampi(copy_from, 0, stroke_frames.size() - 1)]])[0])
	else:
		var blank := PackedByteArray()
		blank.resize(cell_count)
		frames.insert(at, blank)
		stroke_frames.insert(at, [])


func remove_frame(i: int) -> void:
	if is_static:
		return
	if i < frames.size():
		frames.remove_at(i)
	if i < stroke_frames.size():
		stroke_frames.remove_at(i)


func swap_frames(a: int, b: int) -> void:
	if is_static:
		return
	var t := frames[a]
	frames[a] = frames[b]
	frames[b] = t
	while stroke_frames.size() < frames.size():
		stroke_frames.append([])
	var u = stroke_frames[a]
	stroke_frames[a] = stroke_frames[b]
	stroke_frames[b] = u



## JSON turns ints into floats; restore the types the shaders expect.
static func normalize_settings(st: Dictionary) -> Dictionary:
	for k in st.keys():
		if DEFAULT_SETTINGS.has(k):
			match typeof(DEFAULT_SETTINGS[k]):
				TYPE_INT:
					st[k] = int(st[k])
				TYPE_BOOL:
					st[k] = bool(st[k])
				TYPE_FLOAT:
					st[k] = float(st[k])
	for sl in st.get("patterns", []):
		for k in ["source", "seed", "octaves", "mode", "iterations", "drives", "style_count"]:
			if sl.has(k):
				sl[k] = int(sl[k])
		if sl.has("styles"):
			sl.styles = (sl.styles as Array).map(func(x): return int(x))
		if sl.has("colors"):
			sl.colors = (sl.colors as Array).map(func(x): return int(x))
	return st
