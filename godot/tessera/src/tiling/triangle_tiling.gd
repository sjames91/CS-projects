class_name TriangleTiling
extends Tiling
## Equilateral triangles, side = cell size, in rows of height cs*sqrt(3)/2.
## Triangle (col,row) is centered horizontally at x = col*cs/2 and points up
## when (col+row) is even.

var _h: float


func id() -> String:
	return "triangle"


func display_name() -> String:
	return "Triangle"


func _on_setup() -> void:
	_h = cs * sqrt(3.0) * 0.5


func compute_grid() -> Vector2i:
	var h := cs * sqrt(3.0) * 0.5
	return Vector2i(int(ceil(canvas_px.x / (cs * 0.5))) + 2, int(ceil(canvas_px.y / h - 0.001)))


func is_up(c: Vector2i) -> bool:
	return ((c.x + c.y) & 1) == 0


func cell_center(c: Vector2i) -> Vector2:
	var y := c.y * _h + (_h * 2.0 / 3.0 if is_up(c) else _h / 3.0)
	return Vector2(c.x * cs * 0.5, y)


func cell_polygon(c: Vector2i) -> PackedVector2Array:
	var x := c.x * cs * 0.5
	var top := c.y * _h
	var bot := top + _h
	if is_up(c):
		return PackedVector2Array([Vector2(x, top), Vector2(x + cs * 0.5, bot), Vector2(x - cs * 0.5, bot)])
	return PackedVector2Array([Vector2(x - cs * 0.5, top), Vector2(x + cs * 0.5, top), Vector2(x, bot)])


func point_to_cell(p: Vector2) -> Vector2i:
	var fx := p.x / (cs * 0.5)
	var fy := p.y / _h
	var s := int(floor(fx))
	var j := int(floor(fy))
	var u := fx - s
	var v := fy - j
	var right := Vector2i(s + 1, j)
	var inside_right := (u + v > 1.0) if is_up(right) else (u > v)
	return right if inside_right else Vector2i(s, j)


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cand: Array[Vector2i] = [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + (Vector2i(0, 1) if is_up(c) else Vector2i(0, -1))]
	for n in cand:
		if in_grid(n):
			out.append(n)
	return out


func inradius() -> float:
	return cs / (2.0 * sqrt(3.0))


func cell_range_for_rect(r: Rect2) -> Rect2i:
	var a := Vector2i(int(floor(r.position.x / (cs * 0.5))) - 2, int(floor(r.position.y / _h)) - 1)
	var b := Vector2i(int(ceil(r.end.x / (cs * 0.5))) + 2, int(ceil(r.end.y / _h)) + 1)
	return Rect2i(a, b - a)


func rotation_step_deg() -> float:
	return 60.0


func staggered_rows() -> bool:
	return true


func snap_pivot(p: Vector2) -> Vector2:
	# 60 degree steps only map the lattice onto itself about a vertex.
	var best := p
	var best_d := INF
	for v in cell_polygon(point_to_cell(p)):
		var d := p.distance_squared_to(v)
		if d < best_d:
			best_d = d
			best = v
	return best


func glsl() -> String:
	return """
bool TL_up(ivec2 c) { return ((c.x + c.y) & 1) == 0; }
ivec2 TL_cell(vec2 p, float cs, vec4 tp) {
	float h = cs * sqrt(3.0) * 0.5;
	float fx = p.x / (cs * 0.5);
	float fy = p.y / h;
	int s = int(floor(fx));
	int j = int(floor(fy));
	float u = fx - float(s);
	float v = fy - float(j);
	ivec2 right = ivec2(s + 1, j);
	bool inside = TL_up(right) ? (u + v > 1.0) : (u > v);
	return inside ? right : ivec2(s, j);
}
vec2 TL_center(ivec2 c, float cs, vec4 tp) {
	float h = cs * sqrt(3.0) * 0.5;
	float y = float(c.y) * h + (TL_up(c) ? h * 2.0 / 3.0 : h / 3.0);
	return vec2(float(c.x) * cs * 0.5, y);
}
float TL_inradius(float cs) { return cs / (2.0 * sqrt(3.0)); }
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) {
	vec2 q = p - TL_center(c, cs, tp);
	if (TL_up(c)) { q.y = -q.y; }
	float inr = max(cs / (2.0 * sqrt(3.0)) - inset - rnd, 0.0);
	float r = inr * sqrt(3.0);
	float k = sqrt(3.0);
	q.x = abs(q.x) - r;
	q.y = q.y + r / k;
	if (q.x + k * q.y > 0.0) { q = vec2(q.x - k * q.y, -k * q.x - q.y) / 2.0; }
	q.x -= clamp(q.x, -2.0 * r, 0.0);
	return -length(q) * sign(q.y) - rnd;
}
"""
