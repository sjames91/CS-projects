extends Node
## Compute-shader runner (autoload "Gpu"). Owns a local RenderingDevice and
## compiles kernels from GLSL source on first use. All heavy per-cell /
## per-pixel work goes through here, never through GDScript loops.

var rd: RenderingDevice
var _shaders := {}  # key -> {shader, pipeline}
var last_error := ""


func _ready() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("Compute shaders need the Forward+ or Mobile renderer (Vulkan/Metal/D3D12).")


func available() -> bool:
	return rd != null


func _exit_tree() -> void:
	if rd == null:
		return
	for k in _shaders:
		rd.free_rid(_shaders[k].pipeline)
		rd.free_rid(_shaders[k].shader)
	_shaders.clear()
	rd.free()
	rd = null


func _get_kernel(key: String, code: String) -> Dictionary:
	if _shaders.has(key):
		return _shaders[key]
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = code
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		last_error = spirv.compile_error_compute
		push_error("Kernel %s failed to compile:\n%s" % [key, last_error])
		return {}
	var shader := rd.shader_create_from_spirv(spirv, key)
	var pipeline := rd.compute_pipeline_create(shader)
	_shaders[key] = {"shader": shader, "pipeline": pipeline}
	return _shaders[key]


static func pad4(b: PackedByteArray) -> PackedByteArray:
	var out := b.duplicate()
	var rem := out.size() % 4
	if rem != 0 or out.is_empty():
		out.resize(out.size() + (4 - rem if rem != 0 else 4))
	return out


## Run a kernel once. buffers[i] binds to set 0 binding i. Returns the
## contents of the buffers listed in read_back, in order.
func run(key: String, code: String, buffers: Array, push: PackedByteArray, groups: Vector3i, read_back: Array) -> Array:
	if rd == null:
		return []
	var k := _get_kernel(key, code)
	if k.is_empty():
		return []
	var rids: Array[RID] = []
	var uniforms: Array[RDUniform] = []
	for i in buffers.size():
		var data := pad4(buffers[i])
		var buf := rd.storage_buffer_create(data.size(), data)
		rids.append(buf)
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buf)
		uniforms.append(u)
	var uset := rd.uniform_set_create(uniforms, k.shader, 0)
	var pc := push.duplicate()
	if pc.size() % 16 != 0:
		pc.resize(pc.size() + 16 - pc.size() % 16)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, k.pipeline)
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	if pc.size() > 0:
		rd.compute_list_set_push_constant(cl, pc, pc.size())
	rd.compute_list_dispatch(cl, max(groups.x, 1), max(groups.y, 1), max(groups.z, 1))
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var out: Array = []
	for idx in read_back:
		out.append(rd.buffer_get_data(rids[idx]))
	rd.free_rid(uset)
	for r in rids:
		rd.free_rid(r)
	return out


# ---- push-constant packing --------------------------------------------------

class Push:
	var bytes := PackedByteArray()

	func f(v: float) -> Push:
		var o := bytes.size()
		bytes.resize(o + 4)
		bytes.encode_float(o, v)
		return self

	func i(v: int) -> Push:
		var o := bytes.size()
		bytes.resize(o + 4)
		bytes.encode_s32(o, v)
		return self

	func v2(v: Vector2) -> Push:
		return f(v.x).f(v.y)

	func v4(v: Vector4) -> Push:
		return f(v.x).f(v.y).f(v.z).f(v.w)


func push() -> Push:
	return Push.new()


# ---- kernels ----------------------------------------------------------------

## Snap an image to the palette (Palette Lock on export).
func palette_snap(img: Image, palette: PackedColorArray, dither: bool, strength: float) -> Image:
	if palette.is_empty() or rd == null:
		return img
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var pal := PackedByteArray()
	for c in palette:
		var lab := OkLab.from_color(c)
		for v in [lab.x, lab.y, lab.z, 0.0, c.r, c.g, c.b, 1.0]:
			var o := pal.size()
			pal.resize(o + 4)
			pal.encode_float(o, v)
	var code := "#version 450\nlayout(local_size_x = 8, local_size_y = 8) in;\n" + \
		"layout(set = 0, binding = 0, std430) restrict buffer Img { uint px[]; } img;\n" + \
		"layout(set = 0, binding = 1, std430) restrict readonly buffer Pal { vec4 v[]; } pal;\n" + \
		"layout(push_constant, std430) uniform P { int w; int h; int count; int dither; float strength; } pc;\n" + \
		"#define PAL_LAB(i) pal.v[(i) * 2].xyz\n#define PAL_RGB(i) pal.v[(i) * 2 + 1].rgb\n" + \
		OkLab.GLSL + OkLab.BAYER_GLSL + OkLab.SNAP_GLSL + """
void main() {
	ivec2 g = ivec2(gl_GlobalInvocationID.xy);
	if (g.x >= pc.w || g.y >= pc.h) { return; }
	int i = g.y * pc.w + g.x;
	vec4 c = unpackUnorm4x8(img.px[i]);
	if (c.a <= 0.0) { return; }
	vec3 rgb = snap_pick(rgb_to_oklab(c.rgb), g, pc.count, pc.dither != 0, pc.strength);
	img.px[i] = packUnorm4x8(vec4(rgb, c.a));
}
"""
	var w := src.get_width()
	var h := src.get_height()
	var pc := push().i(w).i(h).i(palette.size()).i(1 if dither else 0).f(strength)
	var res := run("palette_snap", code, [src.get_data(), pal], pc.bytes, Vector3i(ceili(w / 8.0), ceili(h / 8.0), 1), [0])
	if res.is_empty():
		return img
	var data: PackedByteArray = res[0]
	data.resize(w * h * 4)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


## Exact unique opaque colours of an image, in order of first appearance.
## Returns {colors: PackedColorArray, overflow: bool}.
func unique_colors(img: Image, max_colors := 256) -> Dictionary:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var table := 4096
	var keys := PackedByteArray()
	keys.resize(table * 4)
	keys.fill(0xFF)
	var first := keys.duplicate()
	var ctr := PackedByteArray()
	ctr.resize(16)
	var n := src.get_width() * src.get_height()
	var code := """#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer Img { uint px[]; } img;
layout(set = 0, binding = 1, std430) restrict buffer Keys { uint k[]; } keys;
layout(set = 0, binding = 2, std430) restrict buffer First { uint f[]; } first;
layout(set = 0, binding = 3, std430) restrict buffer Ctr { uint overflow; } ctr;
layout(push_constant, std430) uniform P { int n; int table; } pc;
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(pc.n)) { return; }
	uint col = img.px[i];
	if ((col >> 24u) < 128u) { return; }
	col |= 0xFF000000u;
	uint mask = uint(pc.table - 1);
	uint slot = (col * 2654435761u) & mask;
	for (int t = 0; t < pc.table; t++) {
		uint prev = atomicCompSwap(keys.k[slot], 0xFFFFFFFFu, col);
		if (prev == 0xFFFFFFFFu || prev == col) { atomicMin(first.f[slot], i); return; }
		slot = (slot + 1u) & mask;
	}
	atomicAdd(ctr.overflow, 1u);
}
"""
	var res := run("unique_colors", code, [src.get_data(), keys, first, ctr], push().i(n).i(table).bytes, Vector3i(ceili(n / 64.0), 1, 1), [1, 2, 3])
	if res.is_empty():
		return {"colors": PackedColorArray(), "overflow": false}
	var k: PackedByteArray = res[0]
	var f: PackedByteArray = res[1]
	var entries: Array = []
	for s in table:
		var key := k.decode_u32(s * 4)
		if key != 0xFFFFFFFF:
			entries.append([f.decode_u32(s * 4), key])
	entries.sort_custom(func(a, b): return a[0] < b[0])
	var cols := PackedColorArray()
	for e in entries:
		if cols.size() >= max_colors:
			break
		var v: int = e[1]
		cols.append(Color8(v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF))
	var overflow: bool = (res[2] as PackedByteArray).decode_u32(0) > 0 or entries.size() > max_colors
	return {"colors": cols, "overflow": overflow, "total": entries.size()}


## Reduce an image to n colours with k-means in OKLab. Assignment and
## accumulation run on the GPU; only the n centroids are touched on the CPU.
func reduce_colors(img: Image, n: int, iterations := 16) -> PackedColorArray:
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var scale := minf(1.0, 256.0 / maxf(src.get_width(), src.get_height()))
	if scale < 1.0:
		src.resize(maxi(1, int(src.get_width() * scale)), maxi(1, int(src.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	var count := src.get_width() * src.get_height()
	# Farthest-point initialisation on a small sample (n * 1024 distance tests).
	var sample := src.duplicate() as Image
	sample.resize(32, 32, Image.INTERPOLATE_NEAREST)
	var pts: Array[Vector3] = []
	var sd := sample.get_data()
	for i in range(0, sd.size(), 4):
		if sd[i + 3] >= 128:
			pts.append(OkLab.from_color(Color8(sd[i], sd[i + 1], sd[i + 2])))
	if pts.is_empty():
		return PackedColorArray()
	var cents: Array[Vector3] = [pts[0]]
	var mind: Array[float] = []
	for p in pts:
		mind.append(p.distance_squared_to(pts[0]))
	while cents.size() < n:
		var bi := 0
		for i in pts.size():
			if mind[i] > mind[bi]:
				bi = i
		if mind[bi] <= 0.0:
			break
		cents.append(pts[bi])
		for i in pts.size():
			mind[i] = minf(mind[i], pts[i].distance_squared_to(pts[bi]))
	var k := cents.size()
	var code := "#version 450\nlayout(local_size_x = 64) in;\n" + \
		"layout(set = 0, binding = 0, std430) restrict readonly buffer Img { uint px[]; } img;\n" + \
		"layout(set = 0, binding = 1, std430) restrict readonly buffer Cent { vec4 c[]; } cent;\n" + \
		"layout(set = 0, binding = 2, std430) restrict buffer Acc { uint a[]; } acc;\n" + \
		"layout(push_constant, std430) uniform P { int n; int k; } pc;\n" + OkLab.GLSL + """
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= uint(pc.n)) { return; }
	vec4 col = unpackUnorm4x8(img.px[i]);
	if (col.a < 0.5) { return; }
	vec3 lab = rgb_to_oklab(col.rgb);
	int best = 0; float bd = 1e9;
	for (int j = 0; j < pc.k; j++) {
		vec3 d = lab - cent.c[j].xyz;
		float dd = dot(d, d);
		if (dd < bd) { bd = dd; best = j; }
	}
	atomicAdd(acc.a[best * 4 + 0], uint(clamp(lab.x, 0.0, 1.0) * 10000.0));
	atomicAdd(acc.a[best * 4 + 1], uint(clamp(lab.y + 0.5, 0.0, 1.0) * 10000.0));
	atomicAdd(acc.a[best * 4 + 2], uint(clamp(lab.z + 0.5, 0.0, 1.0) * 10000.0));
	atomicAdd(acc.a[best * 4 + 3], 1u);
}
"""
	var data := src.get_data()
	for _it in iterations:
		var cb := PackedByteArray()
		cb.resize(k * 16)
		for j in k:
			cb.encode_float(j * 16, cents[j].x)
			cb.encode_float(j * 16 + 4, cents[j].y)
			cb.encode_float(j * 16 + 8, cents[j].z)
		var acc := PackedByteArray()
		acc.resize(k * 16)
		var res := run("kmeans", code, [data, cb, acc], push().i(count).i(k).bytes, Vector3i(ceili(count / 64.0), 1, 1), [2])
		if res.is_empty():
			break
		var a: PackedByteArray = res[0]
		var moved := 0.0
		for j in k:
			var cnt := a.decode_u32(j * 16 + 12)
			if cnt == 0:
				continue
			var nc := Vector3(a.decode_u32(j * 16) / 10000.0 / cnt, a.decode_u32(j * 16 + 4) / 10000.0 / cnt - 0.5, a.decode_u32(j * 16 + 8) / 10000.0 / cnt - 0.5)
			moved = maxf(moved, nc.distance_to(cents[j]))
			cents[j] = nc
		if moved < 0.0005:
			break
	var out := PackedColorArray()
	for c in cents:
		out.append(OkLab.to_color(c))
	return OkLab.sort_into_ramps(out)


## Resample a layer's cells from one tiling to another (tiling change, canvas
## resize). Each destination cell takes the source cell under its center,
## after shifting by `offset` canvas px.
func resample_cells(src_cells: PackedByteArray, src: Tiling, dst: Tiling, offset: Vector2) -> PackedByteArray:
	var n := dst.cell_count()
	if rd == null:
		var empty := PackedByteArray()
		empty.resize(n)
		return empty
	var key := "resample_%s_%s" % [src.shader_key(), dst.shader_key()]
	var code := "#version 450\nlayout(local_size_x = 64) in;\n" + \
		"layout(set = 0, binding = 0, std430) restrict readonly buffer Src { uint b[]; } srcb;\n" + \
		"layout(set = 0, binding = 1, std430) restrict writeonly buffer Dst { uint b[]; } dstb;\n" + \
		"layout(push_constant, std430) uniform P { vec4 src_tp; vec4 dst_tp; vec2 offset; float src_cs; float dst_cs; ivec2 src_grid; ivec2 dst_grid; } pc;\n" + \
		src.glsl_prefixed("src_") + dst.glsl_prefixed("dst_") + """
void main() {
	uint w = gl_GlobalInvocationID.x;
	int total = pc.dst_grid.x * pc.dst_grid.y;
	uint word = 0u;
	for (int k = 0; k < 4; k++) {
		int idx = int(w) * 4 + k;
		if (idx >= total) { break; }
		ivec2 c = ivec2(idx % pc.dst_grid.x, idx / pc.dst_grid.x);
		vec2 p = dst_center(c, pc.dst_cs, pc.dst_tp) + pc.offset;
		ivec2 s = src_cell(p, pc.src_cs, pc.src_tp);
		uint v = 0u;
		if (s.x >= 0 && s.y >= 0 && s.x < pc.src_grid.x && s.y < pc.src_grid.y) {
			int si = s.y * pc.src_grid.x + s.x;
			v = (srcb.b[si >> 2] >> uint((si & 3) * 8)) & 255u;
		}
		word |= v << uint(k * 8);
	}
	if (int(w) * 4 < total) { dstb.b[w] = word; }
}
"""
	var out := PackedByteArray()
	out.resize(n)
	var pc := push().v4(src.glsl_params()).v4(dst.glsl_params()).v2(offset).f(src.cs).f(dst.cs) \
		.i(src.grid.x).i(src.grid.y).i(dst.grid.x).i(dst.grid.y)
	var res := run(key, code, [src_cells, out], pc.bytes, Vector3i(ceili(n / 256.0), 1, 1), [1])
	if res.is_empty():
		return out
	var r: PackedByteArray = res[0]
	r.resize(n)
	return r


## Rewrite every cell through a 256-entry lookup table (palette remove /
## reorder / merge keep cells pointing at the same colour).
func remap_cells(cells: PackedByteArray, table: PackedByteArray) -> PackedByteArray:
	var n := cells.size()
	if rd == null or n == 0:
		return cells
	var tbl := PackedByteArray()
	tbl.resize(256 * 4)
	for i in 256:
		tbl.encode_u32(i * 4, table[i] if i < table.size() else i)
	var code := """#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict buffer Cells { uint b[]; } cells;
layout(set = 0, binding = 1, std430) restrict readonly buffer Tbl { uint t[]; } tbl;
layout(push_constant, std430) uniform P { int words; } pc;
void main() {
	uint w = gl_GlobalInvocationID.x;
	if (w >= uint(pc.words)) { return; }
	uint v = cells.b[w];
	uint o = 0u;
	for (uint k = 0u; k < 4u; k++) { o |= tbl.t[(v >> (k * 8u)) & 255u] << (k * 8u); }
	cells.b[w] = o;
}
"""
	var words := ceili(n / 4.0)
	var res := run("remap", code, [cells, tbl], push().i(words).bytes, Vector3i(ceili(words / 64.0), 1, 1), [0])
	if res.is_empty():
		return cells
	var out: PackedByteArray = res[0]
	out.resize(n)
	return out


## Flow field from direction strokes: every texel gets the inverse-distance
## weighted tangent of all stroke segments. Returns an RGF image (x, y).
func flow_field(strokes: Array, size: Vector2i, canvas_px: Vector2) -> Image:
	var segs := PackedFloat32Array()
	for s in strokes:
		for i in range(s.size() - 1):
			segs.append_array([s[i].x, s[i].y, s[i + 1].x, s[i + 1].y])
	var n := segs.size() / 4
	var out := PackedByteArray()
	out.resize(size.x * size.y * 8)
	if rd == null or n == 0:
		return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGF, out)
	var code := """#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer Segs { vec4 s[]; } segs;
layout(set = 0, binding = 1, std430) restrict writeonly buffer Out { vec2 v[]; } outb;
layout(push_constant, std430) uniform P { int w; int h; int n; float falloff; vec2 canvas; } pc;
void main() {
	ivec2 g = ivec2(gl_GlobalInvocationID.xy);
	if (g.x >= pc.w || g.y >= pc.h) { return; }
	vec2 p = (vec2(g) + 0.5) / vec2(pc.w, pc.h) * pc.canvas;
	vec2 acc = vec2(0.0);
	for (int i = 0; i < pc.n; i++) {
		vec2 a = segs.s[i].xy;
		vec2 b = segs.s[i].zw;
		vec2 ab = b - a;
		float len2 = max(dot(ab, ab), 1e-6);
		float t = clamp(dot(p - a, ab) / len2, 0.0, 1.0);
		float d = length(p - (a + ab * t));
		float wgt = sqrt(len2) / (d * d + pc.falloff * pc.falloff);
		acc += normalize(ab) * wgt;
	}
	float l = length(acc);
	outb.v[g.y * pc.w + g.x] = l > 1e-9 ? acc / l : vec2(0.0);
}
"""
	var falloff := maxf(canvas_px.x, canvas_px.y) / 64.0
	var pc := push().i(size.x).i(size.y).i(n).f(falloff).v2(canvas_px)
	var res := run("flow_field", code, [segs.to_byte_array(), out], pc.bytes, Vector3i(ceili(size.x / 8.0), ceili(size.y / 8.0), 1), [1])
	if res.is_empty():
		return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGF, out)
	var data: PackedByteArray = res[0]
	data.resize(size.x * size.y * 8)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGF, data)


## Many dispatches of one kernel in a single compute list with a barrier
## between them (iterative simulations); pushes[i] is dispatch i's constants.
func run_sequence(key: String, code: String, buffers: Array, pushes: Array, groups: Vector3i, read_back: Array) -> Array:
	if rd == null:
		return []
	var k := _get_kernel(key, code)
	if k.is_empty():
		return []
	var rids: Array[RID] = []
	var uniforms: Array[RDUniform] = []
	for i in buffers.size():
		var data := pad4(buffers[i])
		var buf := rd.storage_buffer_create(data.size(), data)
		rids.append(buf)
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buf)
		uniforms.append(u)
	var uset := rd.uniform_set_create(uniforms, k.shader, 0)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, k.pipeline)
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	for pb in pushes:
		var pc: PackedByteArray = pb.duplicate()
		if pc.size() % 16 != 0:
			pc.resize(pc.size() + 16 - pc.size() % 16)
		rd.compute_list_set_push_constant(cl, pc, pc.size())
		rd.compute_list_dispatch(cl, groups.x, groups.y, groups.z)
		rd.compute_list_add_barrier(cl)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var out: Array = []
	for idx in read_back:
		out.append(rd.buffer_get_data(rids[idx]))
	rd.free_rid(uset)
	for r in rids:
		rd.free_rid(r)
	return out
