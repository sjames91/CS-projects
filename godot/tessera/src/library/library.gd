class_name Library
extends RefCounted
## Presets (layer, display, direction, full-stack) and the user library.
## Presets apply settings only and never paint cells. The user library lives
## in the app's user data folder as versioned JSON files and can be exported
## / imported as a zip.

const FORMAT_VERSION := 1
const MIGRATIONS := {}  # version -> function name, one small function per step
const DIR := "user://library"


# ---- built-in layer presets ------------------------------------------------------

static func _slot(over: Dictionary) -> Dictionary:
	var s := Patterns.default_slot()
	s.merge(over, true)
	return s


static func builtin_layer_presets() -> Array:
	var S := LayerData.Style
	var P := Patterns.Src
	var D := Patterns.Drive
	return [
		{"name": "Clean pixel", "settings": {}},
		{"name": "Soft rounded", "settings": {"rounding_on": true, "rounding": 0.7, "rounding_color_aware": true, "rounding_inner": true}},
		{"name": "Mosaic", "settings": {"style": S.MOSAIC, "gap_on": true, "gap": 0.12, "grout_color": "#2b2a28", "jitter_on": true, "jitter_pos": 0.08, "jitter_size": 0.05, "jitter_rot": 0.06}},
		{"name": "Stained glass", "tiling": "voronoi", "tiling_params": {"jitter": 0.9, "seed": 7}, "settings": {"gap_on": true, "gap": 0.14, "grout_color": "#101010", "rounding_on": true, "rounding": 0.25,
			"patterns": [_slot({"source": P.FRACTAL, "drives": 0, "fine": true, "fine_amount": 0.35, "scale": 2.0})]}},
		{"name": "Cross-stitch", "settings": {"style": S.CROSS_STITCH, "dot_size": 1.0, "stamp_thickness": 0.35}},
		{"name": "LED board", "settings": {"style": S.LED, "dot_size": 0.7, "gap_on": true, "gap": 0.02, "grout_color": "#070707"}},
		{"name": "Lite-Brite", "tiling": "hex", "settings": {"style": S.LITE_BRITE, "dot_size": 0.75}},
		{"name": "Fish scale", "shape": "Fish scale", "settings": {"gap_on": true, "gap": 0.05, "grout_color": "#1c2430", "style": S.MOSAIC}},
		{"name": "Puzzle", "shape": "Puzzle piece", "settings": {"gap_on": true, "gap": 0.05, "grout_color": "#222222"}},
		{"name": "Turing spots", "settings": {"patterns": [_slot({"source": P.REACTION_DIFFUSION, "feed": 0.030, "kill": 0.062, "scale": 1.5, "iterations": 3000, "drives": D.VISIBILITY, "visibility": 0.35})]}},
		{"name": "Turing stripes", "settings": {"patterns": [_slot({"source": P.REACTION_DIFFUSION, "feed": 0.078, "kill": 0.061, "scale": 1.0, "iterations": 3000, "drives": D.PALETTE_SHIFT | D.STYLE, "shift": [-2.0, 0.0], "styles": [S.DOT, S.FLAT, S.FLAT]})]}},
		{"name": "Halftone print", "settings": {"style": S.DOT, "patterns": [_slot({"source": P.HALFTONE, "mode": 0, "scale": 3.0, "angle": 15.0, "drives": D.SIZE, "size": [0.15, 1.15]})]}},
		{"name": "Newspaper", "tiling": "diamond", "settings": {"style": S.DOT, "patterns": [_slot({"source": P.LIGHTNESS, "drives": D.SIZE, "size": [1.2, 0.15]})]}},
		{"name": "Woodcut hatch", "settings": {"patterns": [_slot({"source": P.HATCHING, "mode": 1, "scale": 0.5, "angle": 30.0, "drives": 0, "fine": true, "fine_amount": 0.9})]}},
		{"name": "Knit", "settings": {"gap_on": true, "gap": 0.04, "grout_color": "#2a2020", "patterns": [_slot({"source": P.KNIT, "scale": 1.0, "drives": 0, "fine": true, "fine_amount": 0.8})]}},
		{"name": "Lace cutout", "settings": {"rounding_on": true, "rounding": 0.5, "patterns": [_slot({"source": P.WORLEY, "mode": 1, "scale": 4.0, "drives": D.VISIBILITY, "visibility": 0.35})]}},
		{"name": "Flowing water", "flow": "Wave", "settings": {"style": S.BRUSH_DAB, "dot_size": 0.95, "flow_stamp_rot": true, "flow_patterns": true, "flow_animate": true, "flow_speed": 1.0,
			"patterns": [_slot({"source": P.PERLIN, "scale": 3.0, "drives": D.PALETTE_SHIFT, "shift": [-1.0, 1.0], "fine": true, "fine_amount": 0.3})]}},
		{"name": "Wind grass", "flow": "Uniform direction", "settings": {"style": S.BRUSH_DAB, "dot_size": 0.9, "flow_stamp_rot": true, "jitter_on": true, "jitter_source": 1, "jitter_pos": 0.5, "jitter_rot": 0.3}},
		{"name": "Wood grain", "settings": {"patterns": [_slot({"source": P.WOOD, "scale": 6.0, "turbulence": 0.6, "drives": D.PALETTE_SHIFT, "shift": [-1.0, 1.0], "fine": true, "fine_amount": 0.6})]}},
		{"name": "Brushstroke painting", "flow": "Turbulence", "settings": {"style": S.BRUSH_DAB, "dot_size": 1.0, "flow_stamp_rot": true, "jitter_on": true, "jitter_pos": 0.3, "jitter_size": 0.3, "jitter_rot": 0.2}},
		{"name": "Fur", "flow": "Vortex", "settings": {"style": S.BRUSH_DAB, "dot_size": 0.8, "flow_stamp_rot": true, "jitter_on": true, "jitter_source": 1, "jitter_pos": 0.6,
			"patterns": [_slot({"source": P.FRACTAL, "scale": 2.0, "drives": D.SIZE, "size": [0.6, 1.2]})]}},
	]


## Capture a layer's settings as a preset (no cells).
static func layer_preset_from(layer: LayerData, name_: String) -> Dictionary:
	var p := {"name": name_, "tiling": layer.tiling_id, "tiling_params": layer.tiling_params.duplicate(true),
		"settings": layer.settings.duplicate(true)}
	p.settings.erase("flow_layer")
	if layer.tiling_id.begins_with("shape:"):
		var sid := layer.tiling_id.substr(6)
		if App.project.shapes.has(sid):
			p["shape_data"] = Shape.to_json(App.project.shapes[sid])
	var stamp := str(layer.setting("stamp_shape"))
	if stamp != "" and App.project.shapes.has(stamp):
		p["stamp_data"] = Shape.to_json(App.project.shapes[stamp])
	return p


## Apply a layer preset: one undo step. Settings only; a tiling change maps
## the existing cells into the new tiling (GPU resample).
static func apply_layer_preset(layer: LayerData, preset: Dictionary) -> void:
	App.perform("Preset: " + str(preset.name), func():
		var settings := LayerData.DEFAULT_SETTINGS.duplicate(true)
		settings.merge(preset.get("settings", {}).duplicate(true), true)
		LayerData.normalize_settings(settings)
		settings["flow_layer"] = int(layer.setting("flow_layer"))
		# Shapes the preset needs are embedded in the project.
		var new_tid: String = preset.get("tiling", "square")
		if preset.has("shape"):
			var sh := Shape.builtin(preset.shape)
			sh.id = "builtin_" + str(preset.shape).to_lower().replace(" ", "_")
			if not App.project.shapes.has(sh.id):
				App.project.shapes[sh.id] = sh
			new_tid = "shape:" + sh.id
		if preset.has("shape_data"):
			var sd := Shape.from_json(preset.shape_data)
			App.project.shapes[sd.id] = sd
			new_tid = "shape:" + sd.id
		if preset.has("stamp_data"):
			var st := Shape.from_json(preset.stamp_data)
			App.project.shapes[st.id] = st
			settings["stamp_shape"] = st.id
		App.project.register_shapes()
		var new_params: Dictionary = preset.get("tiling_params", TilingRegistry.default_params(new_tid))
		var old_t := App.tiling_of(layer)
		layer.settings = settings
		if new_tid != layer.tiling_id or new_params != layer.tiling_params:
			layer.tiling_id = new_tid
			layer.tiling_params = new_params.duplicate(true)
		var new_t := App.tiling_of(layer)
		if old_t.shader_key() != new_t.shader_key() or old_t.grid != new_t.grid:
			App.resample_layer(layer, old_t, new_t)
		# Flow presets link (or create) a direction layer with matching strokes.
		if preset.has("flow"):
			var dir_id := 0
			for l in App.project.layers:
				if l.is_direction():
					dir_id = l.id
					break
			if dir_id == 0:
				var d := App.project.add_layer(str(preset.flow), "direction", App.project.layer_index(layer.id) + 1)
				d.strokes_at(0).append_array(DirStroke.preset(str(preset.flow), App.project.canvas_px()))
				dir_id = d.id
			layer.settings["flow_layer"] = dir_id
	, [layer.id])


# ---- full stack / direction presets -------------------------------------------------

static func stack_preset_from(name_: String) -> Dictionary:
	var layers: Array = []
	for l in App.project.layers:
		if not l.is_direction():
			layers.append(layer_preset_from(l, l.name))
	return {"name": name_, "layers": layers, "display": App.project.display.duplicate(true)}


static func apply_stack_preset(preset: Dictionary) -> void:
	var pixel: Array = App.project.layers.filter(func(l): return not l.is_direction())
	var presets: Array = preset.get("layers", [])
	for i in mini(pixel.size(), presets.size()):
		apply_layer_preset(pixel[i], presets[i])
	App.perform("Stack preset display", func(): App.project.display = preset.get("display", {}).duplicate(true))


## Direction strokes stored relative to the canvas so they fit any size.
static func direction_preset_from(layer: LayerData, name_: String) -> Dictionary:
	var px := App.project.canvas_px()
	var strokes: Array = []
	for st in layer.strokes_at(App.frame):
		var j := DirStroke.to_json(st)
		var pts: Array = j.points
		for k in pts.size():
			pts[k] = pts[k] / (px.x if k % 2 == 0 else px.y)
		j.radius = float(j.radius) / px.x
		strokes.append(j)
	return {"name": name_, "strokes": strokes}


static func direction_strokes(preset: Dictionary) -> Array:
	if not preset.has("strokes"):
		return DirStroke.preset(str(preset.name), App.project.canvas_px(), randi() % 1000)
	var px := App.project.canvas_px()
	var out: Array = []
	for j in preset.strokes:
		var c: Dictionary = j.duplicate(true)
		for k in c.points.size():
			c.points[k] = float(c.points[k]) * (px.x if k % 2 == 0 else px.y)
		c.radius = float(c.radius) * px.x
		out.append(DirStroke.from_json(c))
	return out


# ---- user library storage --------------------------------------------------------

static var user := {"layer": [], "display": [], "direction": [], "stack": [], "shapes": []}
static var _loaded := false


static func _path(kind: String) -> String:
	return DIR.path_join(kind + ".json")


static func load_user() -> void:
	_loaded = true
	for kind in user.keys():
		var p := _path(kind)
		if not FileAccess.file_exists(p):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(d) != TYPE_DICTIONARY:
			continue
		d = migrate(d)
		user[kind] = d.get("items", [])


## Upgrade a library file dict to the current format, one step at a time.
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("format_version", 1))
	if v > FORMAT_VERSION:
		App.status.emit("Library file is from a newer version; some items may be missing")
	while v < FORMAT_VERSION:
		if MIGRATIONS.has(v):
			d = Callable(Library, MIGRATIONS[v]).call(d)
		v += 1
	d["format_version"] = FORMAT_VERSION
	return d


static func save_user(kind: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(kind), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"app": "tessera", "kind": kind, "format_version": FORMAT_VERSION, "items": user[kind]}, "\t"))


static func items(kind: String) -> Array:
	if not _loaded:
		load_user()
	return user[kind]


static func add(kind: String, item: Dictionary) -> void:
	items(kind)
	# JSON round trip keeps only plain data (Vector2 etc. serialised).
	user[kind].append(JSON.parse_string(JSON.stringify(_plain(item))))
	save_user(kind)


static func remove(kind: String, index: int) -> void:
	items(kind)
	if index >= 0 and index < user[kind].size():
		user[kind].remove_at(index)
		save_user(kind)


static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2:
			return [v.x, v.y]
		TYPE_PACKED_VECTOR2_ARRAY:
			var a: Array = []
			for p in v:
				a.append_array([p.x, p.y])
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _plain(v[k])
			return d
		TYPE_ARRAY:
			return (v as Array).map(func(x): return _plain(x))
	return v


static func export_zip(path: String) -> Error:
	items("layer")
	var z := ZIPPacker.new()
	var err := z.open(path)
	if err != OK:
		return err
	for kind in user.keys():
		z.start_file(kind + ".json")
		z.write_file(JSON.stringify({"app": "tessera", "kind": kind, "format_version": FORMAT_VERSION, "items": user[kind]}, "\t").to_utf8_buffer())
		z.close_file()
	z.close()
	return OK


## Merge a library zip into the user library.
static func import_zip(path: String) -> int:
	items("layer")
	var r := ZIPReader.new()
	if r.open(path) != OK:
		return -1
	var added := 0
	for kind in user.keys():
		if not r.file_exists(kind + ".json"):
			continue
		var d = JSON.parse_string(r.read_file(kind + ".json").get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY:
			continue
		d = migrate(d)
		for it in d.get("items", []):
			user[kind].append(it)
			added += 1
		save_user(kind)
	r.close()
	return added
