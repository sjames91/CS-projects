class_name ShaderBuilder
extends RefCounted
## Builds canvas_item shaders from a tiling's GLSL snippet. One shader per
## tiling; cell style and features are uniforms (uniform branches are
## coherent across the whole draw, so they cost almost nothing when off).

static var _layer_cache := {}
static var _overlay_cache := {}

const COMMON := """
uniform vec2 canvas_px = vec2(512.0);
uniform vec2 node_origin = vec2(0.0);
uniform vec2 node_size = vec2(512.0);
uniform bool tile_mode = false;

vec2 canvas_point(vec2 uv) {
	vec2 p = node_origin + uv * node_size;
	if (tile_mode) { p = mod(p, canvas_px); }
	return p;
}

vec3 blend_fn(vec3 b, vec3 s, int m) {
	if (m == 1) { return b * s; }
	if (m == 2) { return b + s - b * s; }
	if (m == 3) { return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(vec3(0.5), b)); }
	if (m == 4) { return min(b + s, vec3(1.0)); }
	return s;
}

// Straight-alpha source-over with a separable blend mode (W3C compositing).
vec4 composite(vec4 dst, vec4 src, int m) {
	float as_ = clamp(src.a, 0.0, 1.0);
	float ab = clamp(dst.a, 0.0, 1.0);
	vec3 mixed = (1.0 - ab) * src.rgb + ab * blend_fn(dst.rgb, src.rgb, m);
	float ao = as_ + ab * (1.0 - as_);
	vec3 co = as_ * mixed + ab * dst.rgb * (1.0 - as_);
	return ao > 0.00001 ? vec4(co / ao, ao) : vec4(0.0);
}
"""


static func layer_shader(t: Tiling) -> Shader:
	var key := t.id()
	if _layer_cache.has(key):
		return _layer_cache[key]
	var s := Shader.new()
	s.code = layer_shader_code(t)
	_layer_cache[key] = s
	return s


static func overlay_shader(t: Tiling) -> Shader:
	var key := t.id()
	if _overlay_cache.has(key):
		return _overlay_cache[key]
	var s := Shader.new()
	s.code = overlay_shader_code(t)
	_overlay_cache[key] = s
	return s


static var _compositor := {}


## Blends up to n layer textures in one pass. Each slot is sampled either in
## canvas space (cache images) or screen space (live layer viewports).
static func compositor_shader(n: int) -> Shader:
	if _compositor.has(n):
		return _compositor[n]
	var code := "shader_type canvas_item;\nrender_mode blend_disabled, unshaded;\n"
	for i in n:
		code += "uniform sampler2D t%d : filter_nearest, repeat_enable;\n" % i
	code += "uniform int n = 0;\nuniform int space[%d];\nuniform int mode[%d];\nuniform float op[%d];\nuniform vec4 tint[%d];\n" % [n, n, n, n]
	code += COMMON
	code += "void fragment() {\n\tvec2 p = canvas_point(UV);\n\tvec2 uvc = p / canvas_px;\n\tvec4 acc = vec4(0.0);\n\tvec4 s;\n"
	for i in n:
		code += "\tif (n > %d) { s = (space[%d] == 0 ? texture(t%d, uvc) : texture(t%d, SCREEN_UV)) * tint[%d]; s.a *= op[%d]; acc = composite(acc, s, mode[%d]); }\n" % [i, i, i, i, i, i, i]
	code += "\tCOLOR = acc;\n}\n"
	var sh := Shader.new()
	sh.code = code
	_compositor[n] = sh
	return sh


static func layer_shader_code(t: Tiling) -> String:
	return """shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D cells_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform float ucs = 8.0;
uniform vec4 utp = vec4(0.0);
uniform ivec2 grid = ivec2(1);
uniform int output_mode = 1;   // layers always output straight alpha; the compositor blends
uniform float opacity = 1.0;   // applied by the compositor
uniform int blend_mode = 0;    // applied by the compositor
uniform bool raw_mode = false;

uniform int cell_style = 0;
uniform float dot_size = 0.8;
uniform float stamp_thickness = 0.3;
uniform bool rounding_on = false;
uniform float rounding = 0.4;
uniform bool rounding_color_aware = false;
uniform bool rounding_inner = false;
uniform bool gap_on = false;
uniform float gap = 0.15;
uniform bool grout_on = true;
uniform vec4 grout_color : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform int boundary_mode = 0;
uniform float boundary_width = 0.5;
uniform bool jitter_on = false;
uniform float jitter_pos = 0.25;
uniform float jitter_size = 0.2;
uniform float jitter_rot = 0.2;
uniform float jitter_seed = 1.0;
uniform int jitter_source = 0;   // 0 random, 1 flow
uniform bool flow_on = false;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform bool scan_on = false;
uniform float scan_thickness = 0.4;
uniform float scan_dark = 0.5;
uniform float scan_spacing = 3.0;
uniform bool mask_on = false;
uniform int mask_type = 0;
uniform float mask_strength = 0.5;
uniform float mask_size = 1.0;
uniform bool beam_on = false;
uniform float beam_amount = 0.6;
uniform bool bleed_on = false;
uniform float bleed = 0.5;
""" + COMMON + t.glsl() + """

int cell_val(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= grid.x || c.y >= grid.y) { return 0; }
	return int(round(texelFetch(cells_tex, c, 0).r * 255.0));
}

vec4 pal(int v) { return texelFetch(palette_tex, ivec2(v - 1, 0), 0); }

vec3 cell_hash(ivec2 c, float salt) {
	uint h = uint(c.x) * 73856093u ^ uint(c.y) * 19349663u ^ uint(jitter_seed * 977.0 + salt) * 83492791u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return vec3(float(h & 1023u), float((h >> 10u) & 1023u), float((h >> 20u) & 1023u)) / 1023.0;
}

vec2 rot2(vec2 v, float a) { float c = cos(a); float s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a; vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float bayer8(ivec2 p) {
	int x = p.x & 7; int y = p.y & 7; int xy = x ^ y;
	int v = ((xy & 1) << 5) | ((x & 1) << 4) | ((xy & 2) << 2) | ((x & 2) << 1) | ((xy & 4) >> 1) | ((x & 4) >> 2);
	return (float(v) + 0.5) / 64.0;
}

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Normal of the cell edge facing p: gradient of the cell inflated far past
// p, so it is the edge's own normal even beside a corner (straight runs of
// neighbouring cells then give exactly parallel normals).
vec2 sdf_grad(vec2 p, ivec2 c) {
	float e = 0.35;
	float infl = -2.0 * ucs;
	float d0 = TL_sdf(p, c, ucs, utp, infl, 0.0);
	return vec2(TL_sdf(p + vec2(e, 0.0), c, ucs, utp, infl, 0.0) - d0, TL_sdf(p + vec2(0.0, e), c, ucs, utp, infl, 0.0) - d0);
}

// Nearby cells around p (found by probing points on two rings).
int gather(vec2 p, ivec2 self_c, inout ivec2 found[17]) {
	int n = 0;
	float inr = TL_inradius(ucs);
	for (int ring = 0; ring < 2; ring++) {
		float rad = inr * (ring == 0 ? 0.7 : 1.45);
		for (int k = 0; k < 8; k++) {
			float a = (float(k) + 0.5 * float(ring)) * TAU / 8.0;
			ivec2 c = TL_cell(p + vec2(cos(a), sin(a)) * rad, ucs, utp);
			if (c == self_c) { continue; }
			bool dup = false;
			for (int i = 0; i < n; i++) { if (found[i] == c) { dup = true; } }
			if (!dup && n < 16) { found[n] = c; n++; }
		}
	}
	return n;
}

// Distances from p to nearby cells whose colour test matches:
// x = nearest distance overall; y, z = the two nearest *edges* that are not
// collinear (cells whose closest feature to p is a vertex are not edges).
vec3 constraints(vec2 p, ivec2 found[17], int n, int v, bool want_equal) {
	float dmin = 1e9;
	float e1 = 1e9; vec2 g1 = vec2(0.0);
	float ds[16]; vec2 gs[16]; bool edge[16];
	for (int i = 0; i < n; i++) {
		int cv = cell_val(found[i]);
		bool ok = want_equal ? (cv == v) : (cv != v);
		ds[i] = 1e9; edge[i] = false;
		if (!ok) { continue; }
		float d = TL_sdf(p, found[i], ucs, utp, 0.0, 0.0);
		float h = TL_sdf(p, found[i], ucs, utp, -2.0 * ucs, 0.0) + 2.0 * ucs;
		ds[i] = d;
		dmin = min(dmin, d);
		edge[i] = abs(d - h) < 0.02 * ucs;
		gs[i] = normalize(sdf_grad(p, found[i]) + vec2(1e-6));
		if (edge[i] && d < e1) { e1 = d; g1 = gs[i]; }
	}
	float e2 = 1e9;
	for (int i = 0; i < n; i++) {
		if (edge[i] && dot(gs[i], g1) < 0.95) { e2 = min(e2, ds[i]); }
	}
	return vec3(dmin, e1, e2);
}

// Signed coverage distance (positive = inside): the region within dmin of
// the boundary, with the convex corner between two edges rounded by r.
float corner_sd(vec3 c, float inset, float r) {
	float dmin = c.x - inset;
	float e1 = c.y - inset;
	float e2 = c.z - inset;
	if (r > 0.0 && e1 < r && e2 < r) { return min(r - length(vec2(r - e1, r - e2)), dmin); }
	return dmin;
}

vec3 crt_post(vec3 rgb, vec2 p) {
	if (scan_on) {
		float ph = mod(p.y, max(scan_spacing, 0.5)) / max(scan_spacing, 0.5);
		float w = fwidth(p.y) / max(scan_spacing, 0.5);
		float band = 1.0 - smoothstep(scan_thickness - w, scan_thickness + w, ph);
		rgb *= 1.0 - scan_dark * band;
	}
	if (mask_on) {
		float u = max(mask_size, 0.25);
		vec3 m = vec3(1.0);
		if (mask_type == 0) {
			int k = int(mod(floor(p.x / u), 3.0));
			m = vec3(k == 0 ? 1.0 : 0.0, k == 1 ? 1.0 : 0.0, k == 2 ? 1.0 : 0.0);
		} else if (mask_type == 1) {
			int k = int(mod(floor(p.x / u), 3.0));
			m = vec3(k == 0 ? 1.0 : 0.0, k == 1 ? 1.0 : 0.0, k == 2 ? 1.0 : 0.0);
			float col = floor(p.x / (u * 3.0));
			float fy = fract(p.y / (u * 3.0) + 0.5 * mod(col, 2.0));
			if (fy > 0.82) { m = vec3(0.0); }
		} else {
			float iy = floor(p.y / u);
			float fx = p.x / u + 0.5 * mod(iy, 2.0);
			int k = int(mod(floor(fx), 3.0));
			vec2 f = vec2(fract(fx), fract(p.y / u)) - 0.5;
			float dotm = 1.0 - smoothstep(0.38, 0.5, length(f));
			m = vec3(k == 0 ? 1.0 : 0.0, k == 1 ? 1.0 : 0.0, k == 2 ? 1.0 : 0.0) * dotm;
		}
		rgb *= mix(vec3(1.0), m * 2.4, mask_strength);
	}
	return rgb;
}

vec4 layer_color(vec2 p, float aa) {
	ivec2 c = TL_cell(p, ucs, utp);
	int v = cell_val(c);
	if (raw_mode) { return v > 0 ? pal(v) : vec4(0.0); }
	float inr = TL_inradius(ucs);
	float gap_px = gap_on ? gap * inr : 0.0;
	float rnd_px = rounding_on ? rounding * max(inr - gap_px, 0.0) : 0.0;

	// Colour-aware rounding: same-coloured neighbours merge into one shape.
	if (rounding_on && rounding_color_aware) {
		ivec2 found[17];
		int n = gather(p, c, found);
		vec4 outc = vec4(0.0);
		if (v > 0) {
			float sd = corner_sd(constraints(p, found, n, v, false), gap_px, rnd_px);
			float cover = smoothstep(-aa, aa, sd);
			outc = vec4(pal(v).rgb, pal(v).a * cover);
		}
		if (rounding_inner && outc.a < 0.999) {
			// Fill concave corners of neighbouring colour regions.
			for (int i = 0; i < n; i++) {
				int u = cell_val(found[i]);
				if (u == 0 || u == v) { continue; }
				vec3 fc = constraints(p, found, n, u, true);
				vec2 f = fc.yz - vec2(gap_px);
				float r = rnd_px;
				if (fc.z < 1e8 && f.x < r && f.y < r) {
					float sd = length(vec2(r - f.x, r - f.y)) - r;
					float cov = smoothstep(-aa, aa, sd);
					if (cov > 0.0) { outc = composite(vec4(pal(u).rgb, cov), outc, 0); }
					break;
				}
			}
		}
		if (gap_on && grout_on && (v > 0 || outc.a > 0.0)) { outc = composite(grout_color, outc, 0); }
		outc.rgb = crt_post(outc.rgb, p);
		return outc;
	}

	if (v == 0) { return vec4(0.0); }
	vec4 col = pal(v);
	vec2 ctr = TL_center(c, ucs, utp);

	if (boundary_mode == 1) {
		float d0 = -TL_sdf(p, c, ucs, utp, 0.0, 0.0);
		float w = max(boundary_width * inr, 0.001);
		if (d0 < w) {
			vec2 g = normalize(sdf_grad(p, c) + vec2(1e-6));
			int nv = cell_val(TL_cell(p + g * (d0 + 0.6), ucs, utp));
			if (nv > 0 && nv != v) {
				float t = 0.5 * (1.0 - d0 / w);
				if (bayer8(ivec2(floor(p))) < t) { col = pal(nv); }
			}
		}
	}

	if (bleed_on) {
		vec3 acc = col.rgb; float wsum = 1.0;
		for (int k = 1; k <= 3; k++) {
			float off = float(k) * bleed * inr;
			float wk = (1.0 - float(k) / 4.0) * bleed;
			int lv = cell_val(TL_cell(p - vec2(off, 0.0), ucs, utp));
			int rv = cell_val(TL_cell(p + vec2(off, 0.0), ucs, utp));
			if (lv > 0) { acc += pal(lv).rgb * wk; wsum += wk; }
			if (rv > 0) { acc += pal(rv).rgb * wk; wsum += wk; }
		}
		col.rgb = acc / wsum;
	}

	vec2 q = p;
	float scl = 1.0;
	if (beam_on && cell_style != 7) {
		scl *= mix(1.0, 0.45 + 0.75 * luma(col.rgb), beam_amount);
	}
	if (jitter_on) {
		vec3 h = cell_hash(c, 0.0);
		vec3 h2 = cell_hash(c, 31.0);
		vec2 off = (h.xy - 0.5) * 2.0 * jitter_pos * inr;
		scl *= max(0.05, 1.0 + (h.z - 0.5) * 2.0 * jitter_size);
		float ang = (h2.x - 0.5) * 2.0 * jitter_rot * PI;
		if (jitter_source == 1 && flow_on) {
			// Follow the linked Direction Layer: slide along the flow and
			// turn toward it (rotation amount 1 = fully aligned).
			vec2 f = texture(flow_tex, ctr / canvas_px).rg;
			if (dot(f, f) > 1e-6) {
				off = f * jitter_pos * inr * (0.5 + h.x);
				ang = atan(f.y, f.x) * jitter_rot;
			}
		}
		q = ctr + rot2(p - ctr - off, -ang);
	}
	q = ctr + (q - ctr) / scl;
	vec2 l = q - ctr;
	float tile_d = TL_sdf(q, c, ucs, utp, gap_px, rnd_px) * scl;
	float shape_d = tile_d;
	vec3 rgb = col.rgb;
	float alpha_mul = 1.0;
	float body = max(inr - gap_px, 0.0);
	vec3 hc = cell_hash(c, 7.0);

	if (cell_style == 1) {
		shape_d = (length(l) - dot_size * body) * scl;
	} else if (cell_style == 2) {
		float a = body * 0.92 * dot_size / 0.8;
		float th = max(stamp_thickness * body * 0.6, 0.3);
		float d1 = sd_segment(l, vec2(-a, -a) * 0.7071, vec2(a, a) * 0.7071);
		float d2 = sd_segment(l, vec2(-a, a) * 0.7071, vec2(a, -a) * 0.7071);
		bool top = d2 < d1 + 0.001;
		float d = min(d1, d2) - th;
		shape_d = d * scl;
		float across = clamp(-(d) / th, 0.0, 1.0);
		rgb *= mix(0.65, 1.12, sqrt(across)) * (top ? 1.0 : 0.85);
	} else if (cell_style == 3) {
		float r = max(dot_size * body, 0.5);
		float dist = length(l);
		float core = 1.0 - smoothstep(r * 0.45, r, dist);
		float glow = exp(-max(dist - r * 0.5, 0.0) / (r * 0.45)) * 0.65;
		rgb = rgb * (0.4 + 0.8 * core) + vec3(pow(core, 4.0) * 0.25);
		alpha_mul = clamp(core + glow, 0.0, 1.0);
	} else if (cell_style == 4) {
		float r = max(dot_size * body, 0.5);
		vec2 lp = l;
		float dist = length(lp);
		float peg = 1.0 - smoothstep(r - aa, r + aa, dist);
		float shade = 0.55 + 0.6 * (1.0 - dist / r);
		float spec = (1.0 - smoothstep(0.0, r * 0.35, length(lp - vec2(-0.32, -0.38) * r))) * 0.6;
		vec3 pegc = rgb * shade + vec3(spec);
		rgb = mix(vec3(0.03, 0.03, 0.035), pegc, peg);
	} else if (cell_style == 5) {
		float r = max(dot_size * body, 0.5);
		float ang = atan(l.y, l.x);
		float rr = r * (1.0 + 0.12 * sin(ang * 3.0 + hc.x * 6.283) + 0.07 * sin(ang * 7.0 + hc.y * 12.0));
		vec2 lr = rot2(l, hc.z * 6.283);
		shape_d = (length(lr * vec2(1.0, 1.2)) - rr) * scl;
		rgb *= 0.86 + 0.14 * sin(lr.y / max(inr, 0.5) * 16.0 + hc.x * 4.0);
	} else if (cell_style == 6) {
		float g2 = gap_px + 0.06 * inr;
		float r2 = max(rnd_px, 0.18 * inr);
		shape_d = TL_sdf(q, c, ucs, utp, g2, r2) * scl;
		float e = 0.35;
		vec2 grad = vec2(TL_sdf(q + vec2(e, 0.0), c, ucs, utp, g2, r2) - TL_sdf(q - vec2(e, 0.0), c, ucs, utp, g2, r2),
			TL_sdf(q + vec2(0.0, e), c, ucs, utp, g2, r2) - TL_sdf(q - vec2(0.0, e), c, ucs, utp, g2, r2));
		vec2 nrm = normalize(grad + vec2(1e-6));
		float edge = smoothstep(-0.3 * inr, 0.0, shape_d);
		rgb *= (0.92 + 0.16 * hc.x) * (1.0 + edge * dot(nrm, vec2(-0.7071, -0.7071)) * 0.45);
	} else if (cell_style == 7) {
		float wcell = 2.0 * body;
		float fx = clamp(l.x / max(wcell, 0.001) + 0.5, 0.0, 0.9999);
		int k = int(floor(fx * 3.0));
		float sub = fract(fx * 3.0) - 0.5;
		float inten = k == 0 ? rgb.r : (k == 1 ? rgb.g : rgb.b);
		float spot = beam_on ? mix(1.0, 0.35 + 0.65 * inten, beam_amount) : 1.0;
		vec2 sp = vec2(sub * wcell / 3.0, l.y);
		vec2 hb = vec2(wcell / 3.0 * 0.36 * spot, body * 0.9 * spot);
		vec2 dd = abs(sp) - hb + vec2(hb.x * 0.5);
		float sd = length(max(dd, vec2(0.0))) + min(max(dd.x, dd.y), 0.0) - hb.x * 0.5;
		float lit = 1.0 - smoothstep(-aa, aa, sd * scl);
		vec3 ch = vec3(k == 0 ? 1.0 : 0.0, k == 1 ? 1.0 : 0.0, k == 2 ? 1.0 : 0.0);
		rgb = ch * inten * 1.25 * lit;
	}

	float cover = (1.0 - smoothstep(-aa, aa, shape_d)) * alpha_mul;
	vec4 outc = vec4(rgb, col.a * cover);
	if (cell_style == 4 || cell_style == 7) {
		outc.a = col.a * (1.0 - smoothstep(-aa, aa, tile_d));
	}
	if (gap_on && grout_on) {
		outc = composite(grout_color, outc, 0);
	}
	outc.rgb = crt_post(outc.rgb, p);
	return outc;
}

void fragment() {
	vec2 p = canvas_point(UV);
	vec2 fw = fwidth(node_origin + UV * node_size);
	float aa = max(max(fw.x, fw.y) * 0.5, 0.02);
	COLOR = layer_color(p, aa);
}
"""


static func overlay_shader_code(t: Tiling) -> String:
	return """shader_type canvas_item;
render_mode blend_mix, unshaded;
uniform sampler2D sel_tex : filter_nearest, repeat_disable;
uniform bool has_sel = false;
uniform bool grid_on = true;
uniform vec4 grid_color : source_color = vec4(1.0, 1.0, 1.0, 0.18);
uniform float ucs = 8.0;
uniform vec4 utp = vec4(0.0);
uniform ivec2 grid = ivec2(1);
""" + COMMON + t.glsl() + """
bool sel_at(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= grid.x || c.y >= grid.y) { return false; }
	return texelFetch(sel_tex, c, 0).r > 0.5;
}
void fragment() {
	vec2 raw = node_origin + UV * node_size;
	vec2 p = canvas_point(UV);
	vec2 px = fwidth(raw);
	ivec2 c0 = TL_cell(p, ucs, utp);
	ivec2 cx = TL_cell(p + vec2(px.x, 0.0), ucs, utp);
	ivec2 cy = TL_cell(p + vec2(0.0, px.y), ucs, utp);
	vec4 col = vec4(0.0);
	float density = ucs / max(px.x, 1e-4);
	if (grid_on && density > 5.0 && (c0 != cx || c0 != cy)) {
		col = grid_color;
		col.a *= clamp((density - 5.0) / 6.0, 0.0, 1.0);
	}
	if (has_sel) {
		bool s0 = sel_at(c0);
		if (s0 != sel_at(cx) || s0 != sel_at(cy)) {
			float ants = step(0.5, fract((raw.x + raw.y) / px.x / 10.0 - TIME * 1.5));
			col = vec4(vec3(ants), 1.0);
		} else if (s0) {
			col = mix(col, vec4(0.35, 0.65, 1.0, 1.0), 0.14);
			col.a = max(col.a, 0.14);
		}
	}
	COLOR = col;
}
"""
