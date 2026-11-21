class_name TriangleTiling
extends Tiling
## Right isosceles triangles that line up with the square grid: base = cell
## size, height = half a cell, in rows of height cs/2 (two triangle rows per
## square row). Triangle (col,row) is centered horizontally at x = col*cs/2
## and points up when (col+row) is even, so an up triangle sits on a
## square's bottom edge with its point at the square's center, and a down
## triangle hangs from a square's top edge with its point at the center.
##
## (Before format 4 this tiling was equilateral; ProjectIO converts old
## triangle layers on load.)

var _h: float
var _r: float  # inradius


func id() -> String:
	return "triangle"


func display_name() -> String:
	return "Triangle"


func _on_setup() -> void:
	_h = cs * 0.5
	_r = cs * (sqrt(2.0) - 1.0) * 0.5


func compute_grid() -> Vector2i:
	return Vector2i(int(ceil(canvas_px.x / (cs * 0.5))) + 2, int(ceil(canvas_px.y / (cs * 0.5) - 0.001)))


func is_up(c: Vector2i) -> bool:
	return ((c.x + c.y) & 1) == 0


## The incenter (the same distance from all three sides), so insets and
## rounding shrink every side evenly.
func cell_center(c: Vector2i) -> Vector2:
	var top := c.y * _h
	var y := top + _h - _r if is_up(c) else top + _r
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
	return _r


func cell_range_for_rect(r: Rect2) -> Rect2i:
	var a := Vector2i(int(floor(r.position.x / (cs * 0.5))) - 2, int(floor(r.position.y / _h)) - 1)
	var b := Vector2i(int(ceil(r.end.x / (cs * 0.5))) + 2, int(ceil(r.end.y / _h)) + 1)
	return Rect2i(a, b - a)


## Only a half turn maps this lattice onto itself (a quarter turn would make
## the rows run vertically).
func rotation_step_deg() -> float:
	return 180.0


func staggered_rows() -> bool:
	return true


func snap_pivot(p: Vector2) -> Vector2:
	# Half turns map the lattice onto itself about a vertex.
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
	float h = cs * 0.5;
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
float TL_inradius(float cs) { return cs * (sqrt(2.0) - 1.0) * 0.5; }
vec2 TL_center(ivec2 c, float cs, vec4 tp) {
	float h = cs * 0.5;
	float r = TL_inradius(cs);
	float top = float(c.y) * h;
	return vec2(float(c.x) * cs * 0.5, TL_up(c) ? top + h - r : top + r);
}
// Isosceles triangle with its point at the origin and its base at y = q.y
// (half base q.x). After Inigo Quilez's sdTriangleIsosceles.
float TL_iso(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) {
	vec2 q = p - TL_center(c, cs, tp);
	float r0 = TL_inradius(cs);
	// Shrinking a triangle evenly scales it about its incenter.
	float k = max(r0 - inset - rnd, 0.0) / r0;
	if (k <= 0.0) { return length(q) - rnd; }
	float to_point = (cs * 0.5 - r0) * k;
	vec2 local = TL_up(c) ? vec2(q.x, q.y + to_point) : vec2(q.x, -q.y + to_point);
	return TL_iso(local, vec2(cs * 0.5 * k, cs * 0.5 * k)) - rnd;
}
"""


## No straight columns (or rows, for Voronoi), so brick offsets do not apply.
func staggered_cols() -> bool:
	return true
