class_name Exporter
extends RefCounted
## Export registry. Each format is an entry in FORMATS; write() dispatches on
## its id. Options (see default_options):
##   format         index into FORMATS
##   scale          layers re-render at this many pixels per canvas pixel
##   raw            raw cells (flat shapes, no Display stack) instead of fully rendered
##   only_selected  the selected layer only, instead of all visible layers
##   repeat         play the animation N times, so animated features
##                  (interlace flicker, static noise, flow drift) get distinct frames
## Palette Lock (App.project.palette_lock) is always the last raster step.

const FORMATS := [
	{"id": "png", "name": "PNG (current frame)", "ext": "png"},
	{"id": "png_zip", "name": "PNG sequence (zip)", "ext": "zip"},
	{"id": "gif", "name": "Animated GIF", "ext": "gif"},
	{"id": "apng", "name": "Animated PNG (APNG)", "ext": "png"},
	{"id": "svg", "name": "SVG (vector cells)", "ext": "svg"},
	{"id": "field", "name": "Direction field image", "ext": "png"},
]


static func default_options() -> Dictionary:
	return {"format": 0, "scale": 1, "raw": false, "only_selected": false, "repeat": 1}


## The layers an export draws.
static func _export_layers(o: Dictionary) -> Array:
	var out: Array = []
	if o.get("only_selected", false):
		var a := App.active_layer()
		if a and not a.is_direction():
			out.append(a)
		return out
	for l in App.project.layers:
		if l.is_direction() or not App.layer_shown(l):
			continue
		out.append(l)
	return out


## Final output for one frame: each layer rendered fresh at export
## resolution, composited on the GPU (with the Display stack unless raw),
## then Palette Lock if it is on.
##   frame          the layers' animation frame
##   display_frame  the frame number animated Display effects use (with
##                  repeat it keeps counting while the layer frames loop)
static func render_frame(host: Node, hub: RenderHub, frame: int, display_frame: int, o: Dictionary) -> Image:
	var scale: int = max(1, int(o.get("scale", 1)))
	var raw: bool = o.get("raw", false)
	var px := App.project.canvas_px()
	var out_size := Vector2i(px * scale)
	var textures := {}
	var ids: Array = []
	for l in _export_layers(o):
		var limg: Image = await hub.render_layer_image(l, frame, out_size, raw)
		textures[l.id] = ImageTexture.create_from_image(limg)
		ids.append(l.id)
	var cv := CompositeView.new()
	cv.texture_override = textures
	cv.only_layers = ids
	cv.no_display = raw
	cv.frame_override = frame
	cv.display_frame = float(display_frame)
	cv.size = out_size
	cv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(cv)
	cv.hub = hub
	cv.set_view(float(scale), Vector2.ZERO)
	cv.rebuild()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := cv.get_texture().get_image()
	cv.queue_free()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var lock := App.project.palette_lock
	if lock.get("enabled", false):
		img = Gpu.palette_snap(img, App.project.palette, lock.get("dither", false), lock.get("strength", 0.5))
	return img


## Milliseconds frame f is shown for.
static func frame_ms(f: int) -> int:
	var p := App.project
	var ms := 0
	if f < p.frame_durations.size():
		ms = p.frame_durations[f]
	if ms <= 0:
		ms = int(round(1000.0 / max(1, p.fps)))
	return ms


## Every frame of the animation, played `repeat` times: [{img, ms}].
static func render_sequence(host: Node, hub: RenderHub, o: Dictionary) -> Array:
	var out: Array = []
	var n: int = App.project.frame_count
	var total: int = n * max(1, int(o.get("repeat", 1)))
	for i in total:
		var f := i % n
		out.append({"img": await render_frame(host, hub, f, i, o), "ms": frame_ms(f)})
	return out


static func _with_ext(path: String, ext: String) -> String:
	if path.get_extension().to_lower() == ext:
		return path
	return path + "." + ext


## Writes the export and gives back a status message.
static func write(host: Node, hub: RenderHub, path: String, o: Dictionary) -> String:
	var fmt: Dictionary = FORMATS[clampi(int(o.get("format", 0)), 0, FORMATS.size() - 1)]
	path = _with_ext(path, fmt.ext)
	var err := OK
	match fmt.id:
		"png":
			var img: Image = await render_frame(host, hub, App.frame, App.frame, o)
			err = img.save_png(path)
		"png_zip":
			var seq := await render_sequence(host, hub, o)
			var zip := ZIPPacker.new()
			err = zip.open(path)
			if err == OK:
				var base := path.get_file().get_basename()
				for i in seq.size():
					zip.start_file("%s_%03d.png" % [base, i + 1])
					zip.write_file(seq[i].img.save_png_to_buffer())
					zip.close_file()
				zip.close()
		"gif":
			var seq := await render_sequence(host, hub, o)
			var frames: Array = []
			var delays: Array = []
			for s in seq:
				frames.append(s.img)
				delays.append(max(1, int(round(s.ms / 10.0))))  # GIF counts hundredths of a second
			err = _store(path, Encoders.gif(frames, delays, App.project.palette))
		"apng":
			var seq := await render_sequence(host, hub, o)
			var frames: Array = []
			var delays: Array = []
			for s in seq:
				frames.append(s.img)
				delays.append(s.ms)
			err = _store(path, Encoders.apng(frames, delays))
		"svg":
			err = _store(path, svg_cells(App.frame, max(1, int(o.get("scale", 1))), o).to_utf8_buffer())
		"field":
			var d := App.active_layer()
			if d == null or not d.is_direction():
				return "Select a direction layer to export its field."
			var fimg: Image = hub.flow_image(d.id, App.frame)
			if fimg == null:
				return "That direction layer has no field yet."
			err = fimg.save_png(path)
	if err != OK:
		return "Export failed (%s): %s" % [error_string(err), path.get_file()]
	return "Exported " + path.get_file()


static func _store(path: String, bytes: PackedByteArray) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	return OK


## Vector cells: one polygon per filled cell, in the layer's own tiling,
## colored from the palette. Raster effects (cell styles, patterns, CRT,
## the Display stack) are left out.
static func svg_cells(frame: int, scale: int, o: Dictionary) -> String:
	var p := App.project
	var size := p.canvas_px() * scale
	var lines := PackedStringArray()
	lines.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" shape-rendering="crispEdges">' % [size.x, size.y, size.x, size.y])
	for l in _export_layers(o):
		var t: Tiling = p.tiling_for(l)
		var cells: PackedByteArray = l.cells(frame)
		lines.append('<g id="%s" opacity="%s">' % [l.name.xml_escape(true), str(snappedf(l.opacity, 0.001))])
		for i in cells.size():
			var c: int = cells[i]
			if c == 0 or c > p.palette.size():
				continue
			var poly := t.cell_polygon(t.cell_of_index(i))
			var pts := PackedStringArray()
			for v in poly:
				pts.append("%s,%s" % [str(snappedf(v.x * scale, 0.01)), str(snappedf(v.y * scale, 0.01))])
			lines.append('<polygon points="%s" fill="#%s"/>' % [" ".join(pts), p.palette[c - 1].to_html(false)])
		lines.append("</g>")
	lines.append("</svg>")
	return "\n".join(lines)
