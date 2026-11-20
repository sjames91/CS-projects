class_name VoronoiTiling
extends Tiling
## One jittered seed point per square cell; each cell is the region closest
## to its seed. Lookup searches the 3x3 neighbourhood (same in GLSL), and
## seeds outside the grid do not exist so the canvas is always covered.

var _jitter: float
var _seed: int
var _poly_cache := {}
var _nb_cache := {}


func id() -> String:
	return "voronoi"


func display_name() -> String:
	return "Voronoi"


func param_defs() -> Array:
	return [
		{"key": "jitter", "label": "Jitter", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.8},
		{"key": "seed", "label": "Seed", "min": 0, "max": 9999, "step": 1, "default": 1},
	]


func _on_setup() -> void:
	_jitter = clampf(float(param("jitter", 0.8)), 0.0, 1.0)
	_seed = int(param("seed", 1)) & 0xFFFF
	_poly_cache.clear()
	_nb_cache.clear()


func compute_grid() -> Vector2i:
	return Vector2i(int(ceil(canvas_px.x / cs - 0.001)), int(ceil(canvas_px.y / cs - 0.001)))


static func hash3(x: int, y: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + s * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return h ^ (h >> 16)


func seed_point(c: Vector2i) -> Vector2:
	var h := hash3(c.x, c.y, _seed)
	var j := Vector2(float(h & 0xFFFF), float(h >> 16)) / 65536.0
	return (Vector2(c) + Vector2(0.5, 0.5) + _jitter * (j - Vector2(0.5, 0.5))) * cs


func cell_center(c: Vector2i) -> Vector2:
	return seed_point(c)


func point_to_cell(p: Vector2) -> Vector2i:
	var base := Vector2i(int(floor(p.x / cs)), int(floor(p.y / cs)))
	var best := Tiling.INVALID
	var best_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := base + Vector2i(dx, dy)
			if not in_grid(c):
				continue
			var d := p.distance_squared_to(seed_point(c))
			if d < best_d:
				best_d = d
				best = c
	return best


## Clip a large square around the seed by the bisector with every nearby seed.
## Tracks which neighbour produced each edge so neighbors() is exact.
func _build(c: Vector2i) -> void:
	var s := seed_point(c)
	var big := cs * 2.5
	var poly := PackedVector2Array([s + Vector2(-big, -big), s + Vector2(big, -big), s + Vector2(big, big), s + Vector2(-big, big)])
	var owners: Array = [null, null, null, null]
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var n := c + Vector2i(dx, dy)
			if not in_grid(n):
				continue
			var m := seed_point(n)
			var normal := (m - s).normalized()
			var mid := (m + s) * 0.5
			var res := _clip(poly, owners, mid, normal, n)
			poly = res[0]
			owners = res[1]
	# Clip to canvas so edge cells do not extend forever.
	var bounds := Rect2(Vector2.ZERO, canvas_px).grow(cs)
	for e in [[Vector2(bounds.position.x, 0), Vector2(-1, 0)], [Vector2(bounds.end.x, 0), Vector2(1, 0)],
			[Vector2(0, bounds.position.y), Vector2(0, -1)], [Vector2(0, bounds.end.y), Vector2(0, 1)]]:
		var res2 := _clip(poly, owners, e[0], e[1], null)
		poly = res2[0]
		owners = res2[1]
	_poly_cache[c] = poly
	var nbs: Array[Vector2i] = []
	for o in owners:
		if o != null and not nbs.has(o):
			nbs.append(o)
	_nb_cache[c] = nbs


## Sutherland-Hodgman against half-plane dot(p - mid, normal) <= 0.
## owners[i] is the neighbour that made edge poly[i] -> poly[i+1].
func _clip(poly: PackedVector2Array, owners: Array, mid: Vector2, normal: Vector2, owner) -> Array:
	var out := PackedVector2Array()
	var out_owners: Array = []
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var da := (a - mid).dot(normal)
		var db := (b - mid).dot(normal)
		if da <= 0.0:
			out.append(a)
			if db <= 0.0:
				out_owners.append(owners[i])
			else:
				out_owners.append(owners[i])
				out.append(a.lerp(b, da / (da - db)))
				out_owners.append(owner)
		elif db <= 0.0:
			out.append(a.lerp(b, da / (da - db)))
			out_owners.append(owners[i])
	return [out, out_owners]


func cell_polygon(c: Vector2i) -> PackedVector2Array:
	if not _poly_cache.has(c):
		_build(c)
	return _poly_cache[c]


func neighbors(c: Vector2i) -> Array[Vector2i]:
	if not _nb_cache.has(c):
		_build(c)
	return _nb_cache[c]


func inradius() -> float:
	return cs * 0.5 * (1.0 - 0.35 * _jitter)


func cell_range_for_rect(r: Rect2) -> Rect2i:
	var a := Vector2i(int(floor(r.position.x / cs)) - 2, int(floor(r.position.y / cs)) - 2)
	var b := Vector2i(int(ceil(r.end.x / cs)) + 2, int(ceil(r.end.y / cs)) + 2)
	return Rect2i(a, b - a)


func rotation_step_deg() -> float:
	return 90.0  # approximate: seeds are irregular, cells remap by center


func glsl_params() -> Vector4:
	return Vector4(_jitter, float(_seed), 0.0, 0.0)


func shader_key() -> String:
	return "voronoi_%dx%d" % [grid.x, grid.y]


func glsl() -> String:
	return ("const int TL_GX = %d;\nconst int TL_GY = %d;\n" % [grid.x, grid.y]) + """
uint TL_hash(uint x, uint y, uint s) {
	uint h = x * 374761393u + y * 668265263u + s * 2246822519u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return h ^ (h >> 16u);
}
vec2 TL_center(ivec2 c, float cs, vec4 tp) {
	uint h = TL_hash(uint(c.x), uint(c.y), uint(tp.y));
	vec2 j = vec2(float(h & 65535u), float(h >> 16u)) / 65536.0;
	return (vec2(c) + 0.5 + tp.x * (j - 0.5)) * cs;
}
bool TL_valid(ivec2 c, vec4 tp) { return c.x >= 0 && c.y >= 0 && c.x < TL_GX && c.y < TL_GY; }
ivec2 TL_cell(vec2 p, float cs, vec4 tp) {
	ivec2 base = ivec2(floor(p / cs));
	ivec2 best = ivec2(-1000000);
	float bd = 1e20;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 c = base + ivec2(dx, dy);
			if (!TL_valid(c, tp)) { continue; }
			vec2 d = p - TL_center(c, cs, tp);
			float dd = dot(d, d);
			if (dd < bd) { bd = dd; best = c; }
		}
	}
	return best;
}
float TL_inradius(float cs) { return cs * 0.4; }
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) {
	vec2 m = TL_center(c, cs, tp);
	float k = max(rnd, 0.0001);
	float acc = 0.0;
	float hard = 1e20;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			if (dx == 0 && dy == 0) { continue; }
			ivec2 n = c + ivec2(dx, dy);
			if (!TL_valid(n, tp)) { continue; }
			vec2 o = TL_center(n, cs, tp);
			vec2 dir = normalize(o - m);
			float d = dot((m + o) * 0.5 - p, dir);
			hard = min(hard, d);
			acc += exp(-d / k);
		}
	}
	float inside = (rnd > 0.0001) ? -k * log(max(acc, 1e-20)) : hard;
	return inset - inside;
}
"""


## No straight columns (or rows, for Voronoi), so brick offsets do not apply.
func staggered_cols() -> bool:
	return true


func staggered_rows() -> bool:
	return true
