class_name Patterns
extends RefCounted
## Procedural patterns of pixel types (Layer Settings section 4).
##
## A pattern slot is a dictionary in layer.settings.patterns. Its source is
## evaluated on the GPU at every cell center (compute kernel) into a
## per-cell value map in [0,1]; the layer shader reads that map to drive cell
## properties. The same GLSL library is pasted into the layer shader so the
## optional fine texture is evaluated procedurally at canvas coordinates and
## matches at any export scale. Reaction-diffusion is simulated on a raster
## (iterated compute) and sampled.

const MAX_SLOTS := 4

enum Src { REACTION_DIFFUSION, VALUE_NOISE, PERLIN, FRACTAL, WORLEY, HALFTONE, BAYER, HATCHING, WEAVE, KNIT, WOOD, MARBLE, LIGHTNESS }
const SRC_NAMES := ["Reaction-diffusion", "Value noise", "Perlin noise", "Fractal noise", "Cellular / Worley",
	"Halftone", "Ordered dither (Bayer)", "Hatching", "Fabric weave", "Knit stitch", "Wood grain", "Marble", "Cell lightness (OKLab)"]
## Sub-modes per source (shown as a dropdown when present).
const MODES := {
	Src.WORLEY: ["Scales (F1)", "Cracked mud (F2-F1)", "Stone"],
	Src.HALFTONE: ["Dots", "Lines", "Crosses"],
	Src.BAYER: ["2×2", "4×4", "8×8"],
	Src.HATCHING: ["Hatching", "Cross-hatching"],
}
## Gray-Scott presets: [feed, kill].
const RD_PRESETS := {"Spots": [0.030, 0.062], "Stripes": [0.078, 0.061], "Maze": [0.029, 0.057], "Coral": [0.0545, 0.062], "Cells": [0.0367, 0.0649]}

enum Drive { STYLE = 1, SIZE = 2, ROTATION = 4, ROUNDING = 8, GAP = 16, JITTER = 32, PALETTE_SHIFT = 64, VISIBILITY = 128 }
const DRIVE_NAMES := {
	Drive.STYLE: "Cell style", Drive.SIZE: "Cell size", Drive.ROTATION: "Cell rotation", Drive.ROUNDING: "Rounding amount",
	Drive.GAP: "Gap / grout", Drive.JITTER: "Jitter amount", Drive.PALETTE_SHIFT: "Palette shift", Drive.VISIBILITY: "Visibility (hide below)",
}


static func default_slot() -> Dictionary:
	return {
		"source": Src.FRACTAL, "seed": 1, "scale": 4.0, "contrast": 1.0, "angle": 45.0,
		"octaves": 4, "mode": 0, "turbulence": 0.5,
		"feed": 0.030, "kill": 0.062, "iterations": 2000,
		"drives": Drive.SIZE, "colors": [],
		"styles": [0, 1, 2], "style_count": 2,
		"size": [0.3, 1.0], "rotation": [0.0, 1.0], "rounding": [0.0, 1.0], "gap": [0.0, 0.6],
		"jitter": [0.0, 1.0], "shift": [-2.0, 2.0], "visibility": 0.4,
		"fine": false, "fine_amount": 0.5,
	}


static func slots(layer: LayerData) -> Array:
	return layer.settings.get("patterns", [])


## Does the per-cell map depend on the cells themselves (needs recompute
## when the user paints)?
static func uses_cells(slot: Dictionary) -> bool:
	return int(slot.source) in [Src.LIGHTNESS, Src.HATCHING]


static func params_a(slot: Dictionary) -> Vector4:
	return Vector4(float(slot.scale), float(slot.contrast), float(slot.angle), float(slot.seed))


static func params_b(slot: Dictionary) -> Vector4:
	return Vector4(float(slot.octaves), float(slot.mode), float(slot.turbulence), 0.0)


## Shared GLSL (valid in Godot shading language and GLSL 450, math only).
const GLSL := """
uint ph_u(uint x) { x ^= x >> 16u; x *= 2146121005u; x ^= x >> 15u; x *= 2221713035u; x ^= x >> 16u; return x; }
float ph_h(vec2 i, float s) {
	uint h = ph_u(uint(int(i.x)) * 1597334677u ^ ph_u(uint(int(i.y)) * 3812015801u ^ uint(int(s)) * 2654435761u));
	return float(h) / 4294967295.0;
}
vec2 ph_g(vec2 i, float s) { float a = ph_h(i, s) * 6.2831853; return vec2(cos(a), sin(a)); }
vec2 ph_rot(vec2 v, float a) { float c = cos(a); float s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }
float ph_value(vec2 q, float s) {
	vec2 i = floor(q); vec2 f = fract(q); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ph_h(i, s), ph_h(i + vec2(1.0, 0.0), s), u.x), mix(ph_h(i + vec2(0.0, 1.0), s), ph_h(i + vec2(1.0, 1.0), s), u.x), u.y);
}
float ph_perlin(vec2 q, float s) {
	vec2 i = floor(q); vec2 f = fract(q); vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(ph_g(i, s), f);
	float b = dot(ph_g(i + vec2(1.0, 0.0), s), f - vec2(1.0, 0.0));
	float c = dot(ph_g(i + vec2(0.0, 1.0), s), f - vec2(0.0, 1.0));
	float d = dot(ph_g(i + vec2(1.0, 1.0), s), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.41;
}
float ph_fbm(vec2 q, float s, int oct) {
	float v = 0.0; float amp = 0.5; float norm = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= oct) { break; }
		v += ph_perlin(q, s + float(i) * 17.0) * amp; norm += amp;
		q = q * 2.03 + vec2(13.1, 7.7); amp *= 0.5;
	}
	return v / max(norm, 0.0001);
}
vec2 ph_worley(vec2 q, float s) {
	vec2 i = floor(q); float f1 = 9.0; float f2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = i + vec2(float(x), float(y));
			vec2 pt = c + vec2(ph_h(c, s), ph_h(c, s + 91.0));
			float d = length(q - pt);
			if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
		}
	}
	return vec2(f1, f2);
}
float ph_bayer(ivec2 p, int bits) {
	int v = 0;
	for (int i = 0; i < 3; i++) {
		if (i >= bits) { break; }
		int xb = (p.x >> i) & 1; int yb = (p.y >> i) & 1;
		v = v | (((2 * (xb ^ yb)) + yb) << (2 * (bits - 1 - i)));
	}
	float n = float(1 << (2 * bits));
	return (float(v) + 0.5) / n;
}
// src: pattern source; p: canvas px; a = (scale cells, contrast, angle deg, seed);
// b = (octaves, mode, turbulence, -); L = OKLab lightness of the cell colour.
// fl = (flow.xy, follow strength, drift): patterns bend, stretch and drift
// along a Direction Layer's flow.
float pattern_eval(int src, vec2 p, float cs, vec4 a, vec4 b, float L, vec4 fl) {
	float s = a.w;
	vec2 q = p / (cs * max(a.x, 0.01));
	float ang = radians(a.z);
	float fmag = length(fl.xy);
	if (fmag > 0.001 && fl.z > 0.0) {
		float fa = atan(fl.y, fl.x);
		float fs = fl.z * clamp(fmag, 0.0, 1.0);
		ang = mix(ang, -fa, fs);
		vec2 qr = ph_rot(q, -fa);
		qr.x = qr.x / (1.0 + 3.0 * fs) - fl.w;
		q = ph_rot(qr, fa);
	}
	q += vec2(fract(s * 0.618034) * 517.0, fract(s * 0.754878) * 311.0);
	int mode = int(b.y);
	float v = 0.0;
	if (src == 1) { v = ph_value(q, s); }
	else if (src == 2) { v = 0.5 + 0.5 * ph_perlin(q, s); }
	else if (src == 3) { v = 0.5 + 0.5 * ph_fbm(q, s, int(b.x)); }
	else if (src == 4) {
		vec2 w = ph_worley(q, s);
		if (mode == 0) { v = clamp(w.x, 0.0, 1.0); }
		else if (mode == 1) { v = clamp((w.y - w.x) * 2.0, 0.0, 1.0); }
		else { v = smoothstep(0.02, 0.18, w.y - w.x) * (0.75 + 0.25 * ph_h(floor(q), s)); }
	}
	else if (src == 5) {
		vec2 r = ph_rot(q, ang);
		float lx = 0.5 + 0.5 * cos(r.y * 6.2831853);
		if (mode == 0) { v = clamp(1.0 - length(fract(r) - 0.5) * 1.6, 0.0, 1.0); }
		else if (mode == 1) { v = lx; }
		else { v = max(lx, 0.5 + 0.5 * cos(r.x * 6.2831853)); }
	}
	else if (src == 6) { v = ph_bayer(ivec2(floor(p / cs)), clamp(mode + 1, 1, 3)); }
	else if (src == 7) {
		float dark = 1.0 - clamp(L, 0.0, 1.0);
		vec2 r = ph_rot(q, ang);
		float line = abs(fract(r.y) - 0.5) * 2.0;
		v = 1.0 - smoothstep(dark - 0.08, dark + 0.08, line);
		if (mode == 1 && dark > 0.5) {
			float line2 = abs(fract(r.x) - 0.5) * 2.0;
			v = max(v, 1.0 - smoothstep(dark - 0.58, dark - 0.42, line2));
		}
	}
	else if (src == 8) {
		vec2 r = ph_rot(q, ang);
		vec2 i = floor(r); vec2 f = fract(r);
		bool hz = mod(i.x + i.y, 2.0) < 1.0;
		float across = hz ? f.y : f.x;
		float along = hz ? f.x : f.y;
		v = (1.0 - abs(across - 0.5) * 2.0) * (0.55 + 0.45 * sin(along * 3.14159));
	}
	else if (src == 9) {
		vec2 r = ph_rot(q, ang);
		vec2 f = fract(r);
		float x = abs(f.x - 0.5) * 2.0;
		v = clamp(1.0 - abs(f.y - 0.25 - x * 0.5) * 3.0, 0.0, 1.0) * (0.6 + 0.4 * (1.0 - x));
	}
	else if (src == 10) {
		vec2 c = vec2(ph_h(vec2(3.0, 7.0), s), ph_h(vec2(5.0, 1.0), s)) * 40.0 - 20.0;
		float rr = length(ph_rot(q, ang) * vec2(1.0, 0.25) - c) + ph_fbm(q * 0.5, s, int(b.x)) * b.z * 2.0;
		v = pow(0.5 + 0.5 * sin(rr * 6.2831853), 2.0);
	}
	else if (src == 11) {
		vec2 r = ph_rot(q, ang);
		v = 0.5 + 0.5 * sin((r.x + ph_fbm(q, s, int(b.x)) * b.z * 4.0) * 3.14159);
	}
	else if (src == 12) { v = L; }
	return clamp((v - 0.5) * a.y + 0.5, 0.0, 1.0);
}
"""


# ---- GPU generation -----------------------------------------------------------

## Per-cell map for one slot: RF image (grid sized). `raster` is the
## reaction-diffusion field (or an empty image for other sources).
static func cell_map(slot: Dictionary, t: Tiling, cells: PackedByteArray, palette: PackedColorArray, raster: Image, flow: Image = null, flow_strength := 0.0, drift := 0.0) -> Image:
	var n := t.cell_count()
	var lum := PackedFloat32Array()
	lum.resize(256)
	for i in mini(palette.size(), 255):
		lum[i + 1] = OkLab.lightness(palette[i])
	var rw := 1
	var rh := 1
	var rdata := PackedByteArray()
	rdata.resize(4)
	if raster and not raster.is_empty():
		rw = raster.get_width()
		rh = raster.get_height()
		rdata = raster.get_data()
	var fw := 1
	var fh := 1
	var fdata := PackedByteArray()
	fdata.resize(8)
	if flow and not flow.is_empty() and flow_strength > 0.0:
		fw = flow.get_width()
		fh = flow.get_height()
		fdata = flow.get_data()
	var out := PackedByteArray()
	out.resize(n * 4)
	var code := "#version 450\nlayout(local_size_x = 64) in;\n" + \
		"layout(set = 0, binding = 4, std430) restrict readonly buffer Flow { vec2 f[]; } flowb;\n" + \
		"layout(set = 0, binding = 0, std430) restrict readonly buffer Cells { uint b[]; } cells;\n" + \
		"layout(set = 0, binding = 1, std430) restrict readonly buffer Lum { float l[]; } lum;\n" + \
		"layout(set = 0, binding = 2, std430) restrict readonly buffer Ras { float r[]; } ras;\n" + \
		"layout(set = 0, binding = 3, std430) restrict writeonly buffer Out { float v[]; } outb;\n" + \
		"layout(push_constant, std430) uniform P { vec4 a; vec4 b; vec4 tp; vec2 canvas; float cs; int src; int gw; int gh; int rw; int rh; int fw; int fh; float fs; float drift; } pc;\n" + \
		t.glsl_prefixed("tl_") + GLSL + """
float ras_at(vec2 uv) {
	vec2 x = uv * vec2(pc.rw, pc.rh) - 0.5;
	ivec2 i = ivec2(floor(x)); vec2 f = fract(x);
	ivec2 i00 = ivec2(clamp(i.x, 0, pc.rw - 1), clamp(i.y, 0, pc.rh - 1));
	ivec2 i11 = ivec2(clamp(i.x + 1, 0, pc.rw - 1), clamp(i.y + 1, 0, pc.rh - 1));
	float a = ras.r[i00.y * pc.rw + i00.x]; float b = ras.r[i00.y * pc.rw + i11.x];
	float c = ras.r[i11.y * pc.rw + i00.x]; float d = ras.r[i11.y * pc.rw + i11.x];
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
void main() {
	uint idx = gl_GlobalInvocationID.x;
	if (idx >= uint(pc.gw * pc.gh)) { return; }
	ivec2 c = ivec2(int(idx) % pc.gw, int(idx) / pc.gw);
	vec2 p = tl_center(c, pc.cs, pc.tp);
	uint v8 = (cells.b[idx >> 2u] >> ((idx & 3u) * 8u)) & 255u;
	float L = lum.l[v8];
	float v;
	vec4 fl = vec4(0.0);
	if (pc.fw > 1) {
		ivec2 fi = clamp(ivec2(p / pc.canvas * vec2(pc.fw, pc.fh)), ivec2(0), ivec2(pc.fw - 1, pc.fh - 1));
		fl = vec4(flowb.f[fi.y * pc.fw + fi.x], pc.fs, pc.drift);
	}
	if (pc.src == 0) { v = clamp((ras_at(p / pc.canvas) - 0.5) * pc.a.y + 0.5, 0.0, 1.0); }
	else { v = pattern_eval(pc.src, p, pc.cs, pc.a, pc.b, L, fl); }
	outb.v[idx] = v;
}
"""
	var g := Gpu.push().v4(params_a(slot)).v4(params_b(slot)).v4(t.glsl_params()).v2(t.canvas_px).f(t.cs) \
		.i(int(slot.source)).i(t.grid.x).i(t.grid.y).i(rw).i(rh).i(fw).i(fh).f(flow_strength).f(drift)
	var res := Gpu.run("pattern_cells_" + t.shader_key(), code, [cells, lum.to_byte_array(), rdata, out, fdata], g.bytes, Vector3i(ceili(n / 64.0), 1, 1), [3])
	var data: PackedByteArray = res[0] if not res.is_empty() else out
	data.resize(n * 4)
	return Image.create_from_data(t.grid.x, t.grid.y, false, Image.FORMAT_RF, data)


## Gray-Scott reaction-diffusion on a canvas-space raster. One texel is
## a quarter of `scale` cells, so `scale` sets feature size like the others.
## flow (optional RGF image, same canvas) makes diffusion anisotropic along it.
static func reaction_diffusion(slot: Dictionary, canvas_px: Vector2, cs: float, flow: Image = null, flow_strength := 0.0) -> Image:
	var texel := maxf(cs * float(slot.scale) / 4.0, 0.5)
	var rw := clampi(int(canvas_px.x / texel), 8, 512)
	var rh := clampi(int(canvas_px.y / texel), 8, 512)
	var state := PackedByteArray()
	state.resize(rw * rh * 8 * 2)
	var fdata := PackedByteArray()
	var fw := 1
	var fh := 1
	fdata.resize(8)
	if flow and not flow.is_empty() and flow_strength > 0.0:
		var f2 := flow.duplicate() as Image
		f2.resize(rw, rh, Image.INTERPOLATE_BILINEAR)
		fdata = f2.get_data()
		fw = rw
		fh = rh
	var code := """#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, std430) restrict buffer S { vec2 v[]; } st;
layout(set = 0, binding = 1, std430) restrict readonly buffer F { vec2 f[]; } fl;
layout(set = 0, binding = 2, std430) restrict writeonly buffer O { float v[]; } outb;
layout(push_constant, std430) uniform P { int w; int h; int phase; int seed; float feed; float kill; float aniso; int has_flow; } pc;
uint hh(uint x) { x ^= x >> 16u; x *= 2146121005u; x ^= x >> 15u; x *= 2221713035u; x ^= x >> 16u; return x; }
void main() {
	ivec2 g = ivec2(gl_GlobalInvocationID.xy);
	if (g.x >= pc.w || g.y >= pc.h) { return; }
	int n = pc.w * pc.h;
	int i = g.y * pc.w + g.x;
	if (pc.phase == -2) { outb.v[i] = clamp(st.v[pc.seed * n + i].y * 2.5, 0.0, 1.0); return; }
	if (pc.phase < 0) {
		// Seed blobs: some 8x8 blocks get a small disc of B.
		ivec2 blk = g / 8;
		uint bh = hh(uint(blk.x) * 73856093u ^ uint(blk.y) * 19349663u ^ uint(pc.seed) * 83492791u);
		vec2 ctr = vec2(blk * 8) + 4.0 + (vec2(float(bh & 3u), float((bh >> 2u) & 3u)) - 1.5);
		bool on = float(bh >> 8u) / 16777215.0 < 0.35 && length(vec2(g) - ctr) < 2.6;
		st.v[i] = on ? vec2(0.5, 1.0) : vec2(1.0, 0.0);
		return;
	}
	int src = (pc.phase & 1) * n;
	int dst = n - src;
	vec2 c = st.v[src + i];
	vec2 lap = -c;
	vec2 dir = vec2(0.0);
	if (pc.has_flow != 0) { dir = fl.f[i]; }
	float wsum = 0.0;
	vec2 acc = vec2(0.0);
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) { continue; }
			ivec2 q = ivec2((g.x + dx + pc.w) % pc.w, (g.y + dy + pc.h) % pc.h);
			float w = (dx == 0 || dy == 0) ? 0.2 : 0.05;
			vec2 o = normalize(vec2(float(dx), float(dy)));
			w *= 1.0 + pc.aniso * (abs(dot(o, dir)) * 2.0 - 1.0);
			acc += st.v[src + q.y * pc.w + q.x] * w;
			wsum += w;
		}
	}
	lap = acc / max(wsum, 1e-5) - c;
	float abb = c.x * c.y * c.y;
	vec2 nv = c + vec2(1.0 * lap.x - abb + pc.feed * (1.0 - c.x), 0.5 * lap.y + abb - (pc.kill + pc.feed) * c.y);
	st.v[dst + i] = clamp(nv, 0.0, 1.0);
}
"""
	var iters := clampi(int(slot.iterations), 1, 20000)
	var groups := Vector3i(ceili(rw / 8.0), ceili(rh / 8.0), 1)
	var pushes: Array = []
	for it in range(-1, iters):
		pushes.append(Gpu.push().i(rw).i(rh).i(it).i(int(slot.seed)).f(float(slot.feed)).f(float(slot.kill)) \
			.f(clampf(flow_strength, 0.0, 0.9)).i(1 if fw > 1 else 0).bytes)
	pushes.append(Gpu.push().i(rw).i(rh).i(-2).i(iters & 1).f(0.0).f(0.0).f(0.0).i(0).bytes)
	var outb := PackedByteArray()
	outb.resize(rw * rh * 4)
	var res := Gpu.run_sequence("reaction_diffusion", code, [state, fdata, outb], pushes, groups, [2])
	var data: PackedByteArray = res[0] if not res.is_empty() else outb
	data.resize(rw * rh * 4)
	return Image.create_from_data(rw, rh, false, Image.FORMAT_RF, data)


## GPU bake of palette shift + visibility drives into cell indexes.
## maps: MAX_SLOTS consecutive float maps; cfg: per slot (flags, shift lo,
## shift hi, visibility); filt: per slot 8 filter words + "filtered" flag.
static func flatten(cells: PackedByteArray, maps: PackedByteArray, cfg: PackedFloat32Array, filt: PackedInt32Array, pal_count: int) -> PackedByteArray:
	var n := cells.size()
	var code := """#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict buffer Cells { uint b[]; } cells;
layout(set = 0, binding = 1, std430) restrict readonly buffer Maps { float m[]; } maps;
layout(set = 0, binding = 2, std430) restrict readonly buffer Cfg { vec4 c[]; } cfg;
layout(set = 0, binding = 3, std430) restrict readonly buffer Filt { int f[]; } filt;
layout(push_constant, std430) uniform P { int n; int pal; } pc;
bool applies(int s, int v) {
	if (filt.f[s * 9 + 8] == 0) { return true; }
	return ((filt.f[s * 9 + (v >> 5)] >> (v & 31)) & 1) != 0;
}
void main() {
	uint w = gl_GlobalInvocationID.x;
	if (w >= uint((pc.n + 3) / 4)) { return; }
	uint word = cells.b[w];
	uint outw = 0u;
	for (uint k = 0u; k < 4u; k++) {
		int idx = int(w * 4u + k);
		int v = int((word >> (k * 8u)) & 255u);
		int v0 = v;
		if (idx < pc.n && v > 0) {
			for (int s = 0; s < 4; s++) {
				if (!applies(s, v0)) { continue; }
				int fl = int(cfg.c[s].x);
				float x = maps.m[s * pc.n + idx];
				if ((fl & 128) != 0 && x < cfg.c[s].w) { v = 0; break; }
				if ((fl & 64) != 0) { v = clamp(v + int(round(mix(cfg.c[s].y, cfg.c[s].z, x))), 1, pc.pal); }
			}
		}
		outw |= uint(v & 255) << (k * 8u);
	}
	cells.b[w] = outw;
}
"""
	var words := ceili(n / 4.0)
	var res := Gpu.run("flatten_patterns", code, [cells, maps, cfg.to_byte_array(), filt.to_byte_array()], Gpu.push().i(n).i(maxi(pal_count, 1)).bytes, Vector3i(ceili(words / 64.0), 1, 1), [0])
	if res.is_empty():
		return cells
	var out: PackedByteArray = res[0]
	out.resize(n)
	return out
