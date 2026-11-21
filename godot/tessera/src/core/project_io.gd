class_name ProjectIO
extends RefCounted
## Save / load with a format version on every file. Older files run through
## one small migration function per version step; newer files load with a
## warning instead of crashing.

const FORMAT_VERSION := 4
const APP_ID := "tessera"

## Migration steps: MIGRATIONS[n] upgrades a version-n dict to n+1.
const MIGRATIONS := {
	1: "_migrate_1_to_2",
	2: "_migrate_2_to_3",
	3: "_migrate_3_to_4",
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
		meta.erase("legacy_equilateral")
		# JSON turns ints into floats; normalise the ones that matter.
		meta["id"] = int(meta.get("id", p.next_layer_id))
		meta["blend_mode"] = int(meta.get("blend_mode", 0))
		l.apply_meta(meta)
		LayerData.normalize_settings(l.settings)
		for f in ld.get("frames", []):
			var raw := Marshalls.base64_to_raw(f.zstd)
			l.frames.append(raw.decompress(int(f.size), FileAccess.COMPRESSION_ZSTD))
		var sfr: Array = []
		for fr in ld.get("stroke_frames", [[]]):
			sfr.append(fr.map(func(st): return DirStroke.from_json(st)))
		l.stroke_frames = sfr if not sfr.is_empty() else [[]]
		if ld.get("legacy_equilateral", false):
			_convert_equilateral(l, p)
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


## v3 triangles were equilateral (rows cs*sqrt(3)/2 tall), which never lined
## up with the other tilings. v4 triangles are half a cell tall and line up
## with the square grid. Old triangle layers are marked here and converted
## once their cells are loaded (_convert_equilateral).
static func _migrate_3_to_4(d: Dictionary) -> Dictionary:
	for l in d.get("layers", []):
		if str(l.get("tiling_id", "")) == "triangle":
			l["legacy_equilateral"] = true
	return d


## Each new triangle takes the color of the old equilateral triangle under
## its center. The old layout: triangle (col,row) centered at x = col*cs/2,
## rows h = cs*sqrt(3)/2 tall, pointing up when col+row is even.
static func _convert_equilateral(l: LayerData, p: ProjectData) -> void:
	var cs := float(p.cell_size)
	var px := p.canvas_px()
	var h := cs * sqrt(3.0) * 0.5
	var old_grid := Vector2i(int(ceil(px.x / (cs * 0.5))) + 2, int(ceil(px.y / h - 0.001)))
	var t := p.tiling_for(l)
	for fi in l.frames.size():
		var old := l.frames[fi]
		var out := PackedByteArray()
		out.resize(t.cell_count())
		for i in out.size():
			var c := _equilateral_cell(t.cell_center(t.cell_of_index(i)), cs, h)
			if c.x >= 0 and c.y >= 0 and c.x < old_grid.x and c.y < old_grid.y:
				var oi := c.y * old_grid.x + c.x
				if oi < old.size():
					out[i] = old[oi]
		l.frames[fi] = out


static func _equilateral_cell(pt: Vector2, cs: float, h: float) -> Vector2i:
	var fx := pt.x / (cs * 0.5)
	var fy := pt.y / h
	var s := int(floor(fx))
	var j := int(floor(fy))
	var u := fx - s
	var v := fy - j
	var right := Vector2i(s + 1, j)
	var up_right := ((right.x + right.y) & 1) == 0
	var inside_right := (u + v > 1.0) if up_right else (u > v)
	return right if inside_right else Vector2i(s, j)
