class_name ProjectIO
extends RefCounted
## Save / load with a format version on every file. Older files run through
## one small migration function per version step; newer files load with a
## warning instead of crashing.

const FORMAT_VERSION := 3
const APP_ID := "tessera"

## Migration steps: MIGRATIONS[n] upgrades a version-n dict to n+1.
const MIGRATIONS := {
	1: "_migrate_1_to_2",
	2: "_migrate_2_to_3",
}


static func to_dict(p: ProjectData) -> Dictionary:
	var ls: Array = []
	for l in p.layers:
		var d := l.meta_dict()
		var fr: Array = []
		for f in l.frames:
			fr.append({"size": f.size(), "zstd": Marshalls.raw_to_base64(f.compress(FileAccess.COMPRESSION_ZSTD))})
		d["frames"] = fr
		var sf: Array = []
		for sfr0 in l.stroke_frames:
			sf.append(sfr0.map(func(st): return DirStroke.to_json(st)))
		d["stroke_frames"] = sf
		ls.append(d)
	var pal: Array = []
	for c in p.palette:
		pal.append(c.to_html(true))
	return {
		"app": APP_ID,
		"format_version": FORMAT_VERSION,
		"canvas": {"cells": [p.canvas_cells.x, p.canvas_cells.y], "cell_size": p.cell_size},
		"palette": pal,
		"palette_lock": p.palette_lock,
		"display": p.display,
		"shapes": p.shapes.values().map(func(sh): return Shape.to_json(sh)),
		"animation": {"frame_count": p.frame_count, "fps": p.fps, "durations": Array(p.frame_durations)},
		"next_layer_id": p.next_layer_id,
		"layers": ls,
	}


## Returns {project, warnings: Array[String]} or {error}.
static func from_dict(src: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var d := src.duplicate(true)
	var v := int(d.get("format_version", 1))
	if v > FORMAT_VERSION:
		warnings.append("This file was saved by a newer version of the app (format %d, this app reads %d). Some settings may be missing." % [v, FORMAT_VERSION])
	while v < FORMAT_VERSION:
		if not MIGRATIONS.has(v):
			return {"error": "No migration from format %d" % v}
		d = Callable(ProjectIO, MIGRATIONS[v]).call(d)
		v += 1
		d["format_version"] = v
	var p := ProjectData.new()
	var canvas: Dictionary = d.get("canvas", {})
	var cells: Array = canvas.get("cells", [64, 64])
	p.canvas_cells = Vector2i(int(cells[0]), int(cells[1]))
	p.cell_size = int(canvas.get("cell_size", 8))
	p.palette = PackedColorArray()
	for h in d.get("palette", []):
		p.palette.append(Color.html(h))
	var lock: Dictionary = p.palette_lock.duplicate()
	lock.merge(d.get("palette_lock", {}), true)
	p.palette_lock = lock
	p.display = d.get("display", {})
	for sj in d.get("shapes", []):
		var sh := Shape.from_json(sj)
		p.shapes[sh.id] = sh
	p.register_shapes()
	var anim: Dictionary = d.get("animation", {})
	p.frame_count = max(int(anim.get("frame_count", 1)), 1)
	p.fps = int(anim.get("fps", 12))
	p.frame_durations = PackedInt32Array(anim.get("durations", []))
	p.frame_durations.resize(p.frame_count)
	p.next_layer_id = int(d.get("next_layer_id", 1))
	for ld in d.get("layers", []):
		var l := LayerData.new()
		var meta: Dictionary = ld.duplicate()
		meta.erase("frames")
		meta.erase("stroke_frames")
		# JSON turns ints into floats; normalise the ones that matter.
		meta["id"] = int(meta.get("id", p.next_layer_id))
		meta["blend_mode"] = int(meta.get("blend_mode", 0))
		l.apply_meta(meta)
		for k in l.settings.keys():
			if LayerData.DEFAULT_SETTINGS.has(k) and typeof(LayerData.DEFAULT_SETTINGS[k]) == TYPE_INT:
				l.settings[k] = int(l.settings[k])
		for f in ld.get("frames", []):
			var raw := Marshalls.base64_to_raw(f.zstd)
			l.frames.append(raw.decompress(int(f.size), FileAccess.COMPRESSION_ZSTD))
		var sfr: Array = []
		for fr in ld.get("stroke_frames", [[]]):
			sfr.append(fr.map(func(st): return DirStroke.from_json(st)))
		l.stroke_frames = sfr if not sfr.is_empty() else [[]]
		var n := p.tiling_for(l).cell_count()
		l.ensure_frames(1 if l.is_static else p.frame_count, n)
		p.layers.append(l)
		p.next_layer_id = max(p.next_layer_id, l.id + 1)
	if p.layers.is_empty():
		p.add_layer("Background")
	return {"project": p, "warnings": warnings}


static func save(p: ProjectData, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(p), "\t"))
	return OK


static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"error": "Could not read %s" % path}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "Not a valid project file"}
	return from_dict(parsed)


# ---- migrations (one small function per version step) ----------------------

## v1 stored the canvas as top-level "width"/"height"/"cell" and layer blend
## modes as strings.
static func _migrate_1_to_2(d: Dictionary) -> Dictionary:
	if not d.has("canvas"):
		d["canvas"] = {"cells": [d.get("width", 64), d.get("height", 64)], "cell_size": d.get("cell", 8)}
	for k in ["width", "height", "cell"]:
		d.erase(k)
	for l in d.get("layers", []):
		if typeof(l.get("blend_mode", 0)) == TYPE_STRING:
			l["blend_mode"] = max(LayerData.BLEND_NAMES.find(String(l.blend_mode).capitalize()), 0)
	return d



## v2 stored direction strokes as bare point lists ("strokes"); v3 stores
## typed strokes per frame ("stroke_frames").
static func _migrate_2_to_3(d: Dictionary) -> Dictionary:
	for l in d.get("layers", []):
		if l.has("strokes"):
			var fr: Array = []
			for flat in l.strokes:
				fr.append({"kind": "curve", "type": "path", "points": flat, "radius": 0.0, "strength": 1.0})
			l["stroke_frames"] = [fr]
			l.erase("strokes")
	return d
