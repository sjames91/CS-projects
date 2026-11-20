class_name DiamondTiling
extends Tiling
## Diamonds (squares rotated 45 degrees) whose width and height equal the
## cell size. Rows are half a cell apart and every odd row is shifted half a
## cell right.


func id() -> String:
	return "diamond"


func display_name() -> String:
	return "Diamond"


func compute_grid() -> Vector2i:
	return Vector2i(int(ceil(canvas_px.x / cs)) + 1, int(ceil(2.0 * canvas_px.y / cs)) + 1)


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * cs + (c.y & 1) * cs * 0.5, c.y * cs * 0.5)


func cell_polygon(c: Vector2i) -> PackedVector2Array:
	var o := cell_center(c)
	var h := cs * 0.5
	return PackedVector2Array([o + Vector2(0, -h), o + Vector2(h, 0), o + Vector2(0, h), o + Vector2(-h, 0)])


func _pq_to_cell(pp: int, qq: int) -> Vector2i:
	var row := pp + qq
	return Vector2i((pp - qq - (row & 1)) / 2, row)


func point_to_cell(p: Vector2) -> Vector2i:
	return _pq_to_cell(int(roundf((p.x + p.y) / cs)), int(roundf((p.y - p.x) / cs)))


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var odd := c.y & 1
	var cand: Array[Vector2i] = [
		Vector2i(c.x - 1 + odd, c.y - 1), Vector2i(c.x + odd, c.y - 1),
		Vector2i(c.x - 1 + odd, c.y + 1), Vector2i(c.x + odd, c.y + 1)]
	for n in cand:
		if in_grid(n):
			out.append(n)
	return out


func inradius() -> float:
	return cs / (2.0 * sqrt(2.0))


func cell_range_for_rect(r: Rect2) -> Rect2i:
	var a := Vector2i(int(floor(r.position.x / cs)) - 2, int(floor(r.position.y * 2.0 / cs)) - 2)
	var b := Vector2i(int(ceil(r.end.x / cs)) + 2, int(ceil(r.end.y * 2.0 / cs)) + 2)
	return Rect2i(a, b - a)


func rotation_step_deg() -> float:
	return 90.0


func staggered_rows() -> bool:
	return true


func glsl() -> String:
	return """
ivec2 TL_cell(vec2 p, float cs, vec4 tp) {
	int P = int(round((p.x + p.y) / cs));
	int Q = int(round((p.y - p.x) / cs));
	int row = P + Q;
	return ivec2((P - Q - (row & 1)) / 2, row);
}
vec2 TL_center(ivec2 c, float cs, vec4 tp) {
	return vec2(float(c.x) * cs + float(c.y & 1) * cs * 0.5, float(c.y) * cs * 0.5);
}
float TL_inradius(float cs) { return cs / (2.0 * sqrt(2.0)); }
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) {
	vec2 l = p - TL_center(c, cs, tp);
	vec2 q = abs(vec2(l.x + l.y, l.y - l.x) * 0.70710678);
	vec2 b = vec2(max(cs / (2.0 * sqrt(2.0)) - inset - rnd, 0.0));
	vec2 d = q - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - rnd;
}
"""


## No straight columns (or rows, for Voronoi), so brick offsets do not apply.
func staggered_cols() -> bool:
	return true
