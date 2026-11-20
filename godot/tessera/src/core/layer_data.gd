class_name LayerData
extends RefCounted
## One layer: its own grid of palette indexes (per frame) plus the
## non-destructive settings that decide how it is drawn.
## Cell byte 0 = empty, n = palette entry n-1.

enum Blend { NORMAL, MULTIPLY, SCREEN, OVERLAY, ADD }
const BLEND_NAMES := ["Normal", "Multiply", "Screen", "Overlay", "Add"]

enum Style { FLAT, DOT, CROSS_STITCH, LED, LITE_BRITE, BRUSH_DAB, MOSAIC, CRT }
const STYLE_NAMES := ["Flat", "Dot", "Cross-stitch X", "LED dot", "Lite-Brite peg", "Brush dab", "Mosaic tile", "CRT phosphor"]

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
	"flow_strength": 1.0,
	"flow_rd": false,
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
## Direction layer data: Array of PackedVector2Array strokes in canvas px.
var strokes: Array = []

var _tiling: Tiling = null
var _tiling_key: String = ""


func is_direction() -> bool:
	return kind == "direction"


func tiling(cell_size: float, canvas_px: Vector2) -> Tiling:
	var mode := int(setting("offset_mode"))
	var amount := float(setting("offset_amount"))
	var key := "%s|%s|%s|%s|%d|%s" % [tiling_id, cell_size, canvas_px, JSON.stringify(tiling_params), mode, amount]
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
		"settings": settings.duplicate(true), "strokes": strokes.duplicate(true),
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
	strokes = d.get("strokes", strokes).duplicate(true)


func duplicate_layer(new_id: int) -> LayerData:
	var l := LayerData.new()
	l.apply_meta(meta_dict())
	l.id = new_id
	l.name = name + " copy"
	for f in frames:
		l.frames.append(f.duplicate())
	return l
