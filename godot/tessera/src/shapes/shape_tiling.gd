class_name ShapeTiling
extends Tiling
## A tiling made from a Shape Editor tiling shape: the tile translated over
## its lattice. Implements the same interface as the built-in tilings, so
## tools, fill, selection, patterns and rendering need no changes.
## Curved edges are flattened to a polygon (in cell units) for lookup.

var shape: Dictionary
var _poly := PackedVector2Array()  # cells, centered on the origin
var _u := Vector2.RIGHT
var _v := Vector2.DOWN
var _iu := Vector2.RIGHT
var _iv := Vector2.DOWN
var _i0 := 0
var _j0 := 0
var _offsets: Array = []
var _inr := 0.5


func _init(s: Dictionary = {}) -> void:
	shape = s


func id() -> String:
	return "shape:" + str(shape.get("id", ""))


func display_name() -> String:
	return "Shape: " + str(shape.get("name", "?"))


func compute_grid() -> Vector2i:
	_poly = Shape.polygon(shape, 6)
	var b := Shape.basis(shape)
	_u = b[0]
	_v = b[1]
	var det := _u.x * _v.y - _u.y * _v.x
	if absf(det) < 1e-6:
		det = 1e-6
	_iu = Vector2(_v.y, -_v.x) / det
	_iv = Vector2(-_u.y, _u.x) / det
	_offsets = Shape.neighbor_offsets(shape)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for c in [Vector2.ZERO, Vector2(canvas_px.x, 0), canvas_px, Vector2(0, canvas_px.y)]:
		var q: Vector2 = c / cs
		var ab := Vector2(_iu.dot(q), _iv.dot(q))
		mn = mn.min(ab)
		mx = mx.max(ab)
	_i0 = int(floor(mn.x)) - 1
	_j0 = int(floor(mn.y)) - 1
	_inr = INF
	for i in _poly.size():
		_inr = minf(_inr, Geometry2D.get_closest_point_to_segment(Vector2.ZERO, _poly[i], _poly[(i + 1) % _poly.size()]).length())
	return Vector2i(int(ceil(mx.x)) + 2 - _i0, int(ceil(mx.y)) + 2 - _j0)


func cell_center(c: Vector2i) -> Vector2:
	return (float(c.x + _i0) * _u + float(c.y + _j0) * _v) * cs


func cell_polygon(c: Vector2i) -> PackedVector2Array:
	var ctr := cell_center(c)
	var out := PackedVector2Array()
	for v in _poly:
		out.append(ctr + v * cs)
	return out


func point_to_cell(p: Vector2) -> Vector2i:
	var q := p / cs
	var base := Vector2i(roundi(_iu.dot(q)), roundi(_iv.dot(q)))
	var best := Tiling.INVALID
	var bd := INF
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var lij := base + Vector2i(di, dj)
			var ctr := float(lij.x) * _u + float(lij.y) * _v
			if Geometry2D.is_point_in_polygon(q - ctr, _poly):
				return Vector2i(lij.x - _i0, lij.y - _j0)
			var d := q.distance_squared_to(ctr)
			if d < bd:
				bd = d
				best = Vector2i(lij.x - _i0, lij.y - _j0)
	return best


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in _offsets:
		var n: Vector2i = c + o
		if in_grid(n):
			out.append(n)
	return out


func inradius() -> float:
	return _inr * cs


func cell_range_for_rect(r: Rect2) -> Rect2i:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var q: Vector2 = c / cs
		var ab := Vector2(_iu.dot(q), _iv.dot(q))
		mn = mn.min(ab)
		mx = mx.max(ab)
	var a := Vector2i(int(floor(mn.x)) - 2 - _i0, int(floor(mn.y)) - 2 - _j0)
	var b := Vector2i(int(ceil(mx.x)) + 2 - _i0, int(ceil(mx.y)) + 2 - _j0)
	return Rect2i(a, b - a)


func rotation_step_deg() -> float:
	return 180.0  # every tile is centrally symmetric


func can_flip_h() -> bool:
	return false


func can_flip_v() -> bool:
	return false


func staggered_rows() -> bool:
	return true


func staggered_cols() -> bool:
	return true


func shader_key() -> String:
	return "shape_%s_%d_%dx%d_%d_%d" % [shape.get("id", ""), hash(_poly), grid.x, grid.y, _i0, _j0]


func glsl() -> String:
	var n := _poly.size()
	var pts: Array = []
	for v in _poly:
		pts.append("vec2(%.6f, %.6f)" % [v.x, v.y])
	return """
const int TL_N = %d;
const vec2 TL_POLY[%d] = {%s};
const vec2 TL_U = vec2(%.6f, %.6f);
const vec2 TL_V = vec2(%.6f, %.6f);
const vec2 TL_IU = vec2(%.6f, %.6f);
const vec2 TL_IV = vec2(%.6f, %.6f);
const int TL_I0 = %d;
const int TL_J0 = %d;
const float TL_INR = %.6f;
const float TL_R2 = %.6f;
bool TL_inside(vec2 q) {
	bool c = false;
	for (int i = 0; i < TL_N; i++) {
		int j = i == 0 ? TL_N - 1 : i - 1;
		vec2 a = TL_POLY[i]; vec2 b = TL_POLY[j];
		if (((a.y > q.y) != (b.y > q.y)) && (q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x)) { c = !c; }
	}
	return c;
}
ivec2 TL_cell(vec2 p, float cs, vec4 tp) {
	vec2 q = p / cs;
	ivec2 base = ivec2(round(vec2(dot(TL_IU, q), dot(TL_IV, q))));
	// Test the 9 nearby tiles nearest-first: usually the first one hits.
	float dist[9];
	for (int k = 0; k < 9; k++) {
		ivec2 l = base + ivec2(k %% 3 - 1, k / 3 - 1);
		vec2 ctr = float(l.x) * TL_U + float(l.y) * TL_V;
		dist[k] = dot(q - ctr, q - ctr);
	}
	int first = 4;
	for (int pass = 0; pass < 9; pass++) {
		int bi = -1;
		float bd = 1e20;
		for (int k = 0; k < 9; k++) {
			if (dist[k] < bd) { bd = dist[k]; bi = k; }
		}
		if (bi < 0 || bd > TL_R2) { break; }
		if (pass == 0) { first = bi; }
		ivec2 l = base + ivec2(bi %% 3 - 1, bi / 3 - 1);
		vec2 ctr = float(l.x) * TL_U + float(l.y) * TL_V;
		if (TL_inside(q - ctr)) { return ivec2(l.x - TL_I0, l.y - TL_J0); }
		dist[bi] = 1e30;
	}
	ivec2 lf = base + ivec2(first %% 3 - 1, first / 3 - 1);
	return ivec2(lf.x - TL_I0, lf.y - TL_J0);
}
vec2 TL_center(ivec2 c, float cs, vec4 tp) { return (float(c.x + TL_I0) * TL_U + float(c.y + TL_J0) * TL_V) * cs; }
float TL_inradius(float cs) { return TL_INR * cs; }
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) {
	vec2 q = (p - TL_center(c, cs, tp)) / cs;
	float d = 1e20;
	for (int i = 0; i < TL_N; i++) {
		int j = i == 0 ? TL_N - 1 : i - 1;
		vec2 a = TL_POLY[j]; vec2 e = TL_POLY[i] - a;
		vec2 w = q - a;
		vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
		d = min(d, dot(b, b));
	}
	float sd = sqrt(d) * cs * (TL_inside(q) ? -1.0 : 1.0);
	// Custom outlines: gap insets exactly; plain rounding is not applied
	// (colour-aware rounding works through neighbour constraints).
	return sd + inset;
}
""" % [n, n, ", ".join(pts), _u.x, _u.y, _v.x, _v.y, _iu.x, _iu.y, _iv.x, _iv.y, _i0, _j0, _inr, _r2()]


## Squared circumradius (cells) + margin: tiles farther than this cannot
## contain the point.
func _r2() -> float:
	var r := 0.0
	for v in _poly:
		r = maxf(r, v.length())
	return (r + 0.01) * (r + 0.01)
