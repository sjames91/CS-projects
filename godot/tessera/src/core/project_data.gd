class_name ProjectData
extends RefCounted
## The whole document: canvas, shared palette, layer stack, animation frames.

var canvas_cells: Vector2i = Vector2i(64, 64)
var cell_size: int = 8
var palette: PackedColorArray = PackedColorArray()
var layers: Array[LayerData] = []
var frame_count: int = 1
var frame_durations: PackedInt32Array = PackedInt32Array([0])  # ms, 0 = use fps
var fps: int = 12
var palette_lock: Dictionary = {"enabled": false, "dither": false, "strength": 0.5}
var next_layer_id: int = 1


func canvas_px() -> Vector2:
	return Vector2(canvas_cells * cell_size)


static func default_palette() -> PackedColorArray:
	# A small ramp-ordered starter palette (dark -> light per ramp).
	var hexes := ["#0d0b14", "#2a2633", "#4f4a5c", "#8a8399", "#c9c3d4", "#f4f1f8",
		"#3b1219", "#7a2331", "#c4443d", "#ec8a5a", "#f8c98f",
		"#14321f", "#2a6b3a", "#58a84a", "#a7d86b",
		"#101c3d", "#24479a", "#3f86d6", "#86c6f0",
		"#3d1d4a", "#7d3b8f", "#c36fc4"]
	var p := PackedColorArray()
	for h in hexes:
		p.append(Color.html(h))
	return p


static func create_default() -> ProjectData:
	var p := ProjectData.new()
	p.palette = default_palette()
	p.add_layer("Background")
	return p


func tiling_for(layer: LayerData) -> Tiling:
	var t := layer.tiling(float(cell_size), canvas_px())
	# Cell arrays always match the tiling's grid (cheap size check).
	var n := t.cell_count()
	for i in layer.frames.size():
		if layer.frames[i].size() != n:
			layer.frames[i].resize(n)
	return t


func add_layer(layer_name: String, kind := "pixel", at := -1) -> LayerData:
	var l := LayerData.new()
	l.id = next_layer_id
	next_layer_id += 1
	l.name = layer_name
	l.kind = kind
	if kind == "direction":
		l.is_static = true
	var t := tiling_for(l)
	l.ensure_frames(1 if l.is_static else frame_count, t.cell_count())
	if at < 0 or at > layers.size():
		layers.append(l)
	else:
		layers.insert(at, l)
	return l


func layer_by_id(layer_id: int) -> LayerData:
	for l in layers:
		if l.id == layer_id:
			return l
	return null


func layer_index(layer_id: int) -> int:
	for i in layers.size():
		if layers[i].id == layer_id:
			return i
	return -1


func frame_duration_ms(frame: int) -> int:
	var d := frame_durations[frame] if frame < frame_durations.size() else 0
	return d if d > 0 else int(1000.0 / max(fps, 1))


# ---- undo snapshots -------------------------------------------------------

## Snapshot of document structure. Cell data is copied only for the layer ids
## in `frames_for` (or every layer when frames_for == ["all"]).
func capture_state(frames_for: Array = []) -> Dictionary:
	var all := frames_for.has("all")
	var ls: Array = []
	for l in layers:
		var entry := {"obj": l, "meta": l.meta_dict()}
		if all or frames_for.has(l.id):
			var fr: Array[PackedByteArray] = []
			for f in l.frames:
				fr.append(f.duplicate())
			entry["frames"] = fr
		ls.append(entry)
	return {
		"canvas_cells": canvas_cells, "cell_size": cell_size, "palette": palette.duplicate(),
		"frame_count": frame_count, "frame_durations": frame_durations.duplicate(), "fps": fps,
		"palette_lock": palette_lock.duplicate(), "next_layer_id": next_layer_id, "layers": ls,
	}


func restore_state(s: Dictionary) -> void:
	canvas_cells = s.canvas_cells
	cell_size = s.cell_size
	palette = s.palette.duplicate()
	frame_count = s.frame_count
	frame_durations = s.frame_durations.duplicate()
	fps = s.fps
	palette_lock = s.palette_lock.duplicate()
	next_layer_id = s.next_layer_id
	var ls: Array[LayerData] = []
	for e in s.layers:
		var l: LayerData = e.obj
		l.apply_meta(e.meta)
		if e.has("frames"):
			var fr: Array[PackedByteArray] = []
			for f in e.frames:
				fr.append(f.duplicate())
			l.frames = fr
		ls.append(l)
	layers = ls
