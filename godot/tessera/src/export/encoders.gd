class_name Encoders
extends RefCounted
## Animated GIF (palette + LZW) and APNG (repackaged PNG chunks) writers.


# ---- GIF ---------------------------------------------------------------------

## Palette index (0-based) of every pixel: the nearest palette color in
## OKLab. A pixel under half alpha gets index palette.size(), the
## transparent slot. Colors are matched once each, so flat pixel art is fast.
static func index_image(img: Image, palette: PackedColorArray) -> PackedByteArray:
	var src := img
	if src.get_format() != Image.FORMAT_RGBA8:
		src = img.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var labs: Array = []
	for c in palette:
		labs.append(OkLab.from_color(c))
	var transparent := palette.size()
	var data := src.get_data()
	var n := src.get_width() * src.get_height()
	var out := PackedByteArray()
	out.resize(n)
	var seen := {}
	for i in n:
		var a := data[i * 4 + 3]
		if a < 128:
			out[i] = transparent
			continue
		var key := data.decode_u32(i * 4) & 0x00FFFFFF
		var idx: int = seen.get(key, -1)
		if idx < 0:
			var lab := OkLab.from_color(Color8(data[i * 4], data[i * 4 + 1], data[i * 4 + 2]))
			var best := INF
			idx = 0
			for k in labs.size():
				var d: float = lab.distance_squared_to(labs[k])
				if d < best:
					best = d
					idx = k
			seen[key] = idx
		out[i] = idx
	return out


## Animated GIF that loops forever. delays are in hundredths of a second.
## Uses the palette plus one transparent slot (so up to 255 colors).
static func gif(frames: Array, delays: Array, palette: PackedColorArray) -> PackedByteArray:
	var pal := palette.slice(0, 255)
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var transparent := pal.size()
	var bits := 1
	while (1 << bits) < pal.size() + 1:
		bits += 1
	var out := PackedByteArray()
	out.append_array("GIF89a".to_ascii_buffer())
	_u16(out, w)
	_u16(out, h)
	out.append(0x80 | ((bits - 1) << 4) | (bits - 1))  # global color table
	out.append(transparent)  # background color index
	out.append(0)
	for i in 1 << bits:
		var c: Color = pal[i] if i < pal.size() else Color.BLACK
		out.append(c.r8)
		out.append(c.g8)
		out.append(c.b8)
	# Loop forever.
	out.append_array(PackedByteArray([0x21, 0xFF, 0x0B]))
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	out.append_array(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))
	for fi in frames.size():
		var img: Image = frames[fi]
		# Graphic control: clear to background before the next frame, transparency on.
		out.append_array(PackedByteArray([0x21, 0xF9, 0x04, (2 << 2) | 1]))
		_u16(out, int(delays[fi]) if fi < delays.size() else 10)
		out.append(transparent)
		out.append(0)
		# Image descriptor: whole canvas, no local table.
		out.append(0x2C)
		_u16(out, 0)
		_u16(out, 0)
		_u16(out, img.get_width())
		_u16(out, img.get_height())
		out.append(0)
		var min_code: int = max(2, bits)
		out.append(min_code)
		var packed := _lzw(index_image(img, pal), min_code)
		var p := 0
		while p < packed.size():
			var n: int = min(255, packed.size() - p)
			out.append(n)
			out.append_array(packed.slice(p, p + n))
			p += n
		out.append(0)
	out.append(0x3B)
	return out


static func _u16(out: PackedByteArray, v: int) -> void:
	out.append(v & 0xFF)
	out.append((v >> 8) & 0xFF)


## GIF-flavored LZW: variable code size, clear code, codes packed LSB first.
static func _lzw(indices: PackedByteArray, min_code: int) -> PackedByteArray:
	var clear := 1 << min_code
	var eoi := clear + 1
	var out := PackedByteArray()
	var acc := 0
	var nbits := 0
	var size := min_code + 1
	var next := eoi + 1
	var table := {}
	# Codes first, then packed into bytes at the end.
	var codes := PackedInt32Array()
	var sizes := PackedByteArray()
	codes.append(clear)
	sizes.append(size)
	if indices.is_empty():
		codes.append(eoi)
		sizes.append(size)
	else:
		var prefix: int = indices[0]
		for i in range(1, indices.size()):
			var k: int = indices[i]
			var key := (prefix << 8) | k
			if table.has(key):
				prefix = table[key]
				continue
			codes.append(prefix)
			sizes.append(size)
			if next < 4096:
				table[key] = next
				next += 1
				if next > (1 << size) and size < 12:
					size += 1
			else:
				codes.append(clear)
				sizes.append(size)
				table.clear()
				size = min_code + 1
				next = eoi + 1
			prefix = k
		codes.append(prefix)
		sizes.append(size)
		codes.append(eoi)
		sizes.append(size)
	for i in codes.size():
		acc |= codes[i] << nbits
		nbits += sizes[i]
		while nbits >= 8:
			out.append(acc & 0xFF)
			acc >>= 8
			nbits -= 8
	if nbits > 0:
		out.append(acc & 0xFF)
	return out


# ---- APNG --------------------------------------------------------------------

## Animated PNG that loops forever. delays are in milliseconds. A viewer
## without APNG support shows the first frame.
static func apng(frames: Array, delays: Array) -> PackedByteArray:
	var out := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var seq := 0
	for fi in frames.size():
		var img: Image = frames[fi]
		if img.get_format() != Image.FORMAT_RGBA8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		var chunks := _png_chunks(img.save_png_to_buffer())
		if fi == 0:
			_chunk(out, "IHDR", chunks.IHDR[0])
			var actl := PackedByteArray()
			_u32be(actl, frames.size())
			_u32be(actl, 0)  # loop forever
			_chunk(out, "acTL", actl)
		var fctl := PackedByteArray()
		_u32be(fctl, seq)
		seq += 1
		_u32be(fctl, w)
		_u32be(fctl, h)
		_u32be(fctl, 0)
		_u32be(fctl, 0)
		var ms: int = int(delays[fi]) if fi < delays.size() else 100
		fctl.append((ms >> 8) & 0xFF)
		fctl.append(ms & 0xFF)
		fctl.append(0x03)  # delay denominator 1000 (ms)
		fctl.append(0xE8)
		fctl.append(1)  # dispose: clear to transparent
		fctl.append(0)  # blend: replace
		_chunk(out, "fcTL", fctl)
		for data in chunks.IDAT:
			if fi == 0:
				_chunk(out, "IDAT", data)
			else:
				var fd := PackedByteArray()
				_u32be(fd, seq)
				seq += 1
				fd.append_array(data)
				_chunk(out, "fdAT", fd)
	_chunk(out, "IEND", PackedByteArray())
	return out


## The IHDR and IDAT chunk payloads of a PNG file.
static func _png_chunks(png: PackedByteArray) -> Dictionary:
	var out := {"IHDR": [], "IDAT": []}
	var p := 8
	while p + 8 <= png.size():
		var n := (png[p] << 24) | (png[p + 1] << 16) | (png[p + 2] << 8) | png[p + 3]
		var kind := png.slice(p + 4, p + 8).get_string_from_ascii()
		if out.has(kind):
			out[kind].append(png.slice(p + 8, p + 8 + n))
		p += 12 + n
	return out


static func _u32be(out: PackedByteArray, v: int) -> void:
	out.append((v >> 24) & 0xFF)
	out.append((v >> 16) & 0xFF)
	out.append((v >> 8) & 0xFF)
	out.append(v & 0xFF)


static func _chunk(out: PackedByteArray, kind: String, data: PackedByteArray) -> void:
	_u32be(out, data.size())
	var body := kind.to_ascii_buffer()
	body.append_array(data)
	out.append_array(body)
	_u32be(out, _crc32(body))


static var _crc_table := PackedInt64Array()


static func _crc32(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n in 256:
			var c := n
			for k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
			_crc_table[n] = c
	var crc := 0xFFFFFFFF
	for b in data:
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF
