class_name HexTiling
extends Tiling
## Pointy-top hexagons, flat-to-flat width = cell size, odd rows shifted
## right by half a cell ("odd-r" layout). Row 0 / col 0 are centered on the
## canvas' top / left edge so the whole canvas is covered with no gaps.

var _r: float  # circumradius


func id() -> String:
	return "hex"


func display_name() -> String:
	return "Hexagon"


func _on_setup() -> void:
	_r = cs / sqrt(3.0)


func compute_grid() -> Vector2i:
	var r := cs / sqrt(3.0)
	return Vector2i(int(ceil(canvas_px.x / cs)) + 1, int(ceil(canvas_px.y / (1.5 * r))) + 1)


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(cs * (c.x + 0.5 * (c.y & 1)), 1.5 * _r * c.y)


func cell_polygon(c: Vector2i) -> PackedVector2Array:
	var ctr := cell_center(c)
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		pts.append(ctr + Vector2(cos(a), sin(a)) * _r)
	return pts


func point_to_cell(p: Vector2) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - p.y / 3.0) / _r
	var r := (2.0 / 3.0 * p.y) / _r
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	var qi := int(rx)
	var ri := int(rz)
	return Vector2i(qi + (ri - (ri & 1)) / 2, ri)


const _EVEN: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 1), Vector2i(-1, 1)]
const _ODD: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(0, 1)]


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in (_ODD if (c.y & 1) == 1 else _EVEN):
		var n: Vector2i = c + d
		if in_grid(n):
			out.append(n)
	return out


func inradius() -> float:
	return cs * 0.5


func cell_range_for_rect(r: Rect2) -> Rect2i:
	var a := Vector2i(int(floor(r.position.x / cs)) - 2, int(floor(r.position.y / (1.5 * _r))) - 2)
	var b := Vector2i(int(ceil(r.end.x / cs)) + 2, int(ceil(r.end.y / (1.5 * _r))) + 2)
	return Rect2i(a, b - a)


func rotation_step_deg() -> float:
	return 60.0


func staggered_rows() -> bool:
	return true


func glsl() -> String:
	return """
ivec2 TL_cell(vec2 p, float cs, vec4 tp) {
	float R = cs / sqrt(3.0);
	float q = (sqrt(3.0) / 3.0 * p.x - p.y / 3.0) / R;
	float r = (2.0 / 3.0 * p.y) / R;
	vec3 cube = vec3(q, -q - r, r);
	vec3 rr = round(cube);
	vec3 d = abs(rr - cube);
	if (d.x > d.y && d.x > d.z) { rr.x = -rr.y - rr.z; }
	else if (d.y > d.z) { rr.y = -rr.x - rr.z; }
	else { rr.z = -rr.x - rr.y; }
	int qi = int(rr.x);
	int ri = int(rr.z);
	return ivec2(qi + (ri - (ri & 1)) / 2, ri);
}
vec2 TL_center(ivec2 c, float cs, vec4 tp) {
	float R = cs / sqrt(3.0);
	return vec2(cs * (float(c.x) + 0.5 * float(c.y & 1)), 1.5 * R * float(c.y));
}
float TL_inradius(float cs) { return cs * 0.5; }
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) {
	vec2 q = (p - TL_center(c, cs, tp)).yx;
	float r = max(cs * 0.5 - inset - rnd, 0.0);
	vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	q = abs(q);
	q -= 2.0 * min(dot(k.xy, q), 0.0) * k.xy;
	q -= vec2(clamp(q.x, -k.z * r, k.z * r), r);
	return length(q) * sign(q.y) - rnd;
}
"""


## No straight columns (or rows, for Voronoi), so brick offsets do not apply.
func staggered_cols() -> bool:
	return true
