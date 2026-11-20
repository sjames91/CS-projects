class_name SquareTiling
extends Tiling


func id() -> String:
	return "square"


func display_name() -> String:
	return "Square"


func compute_grid() -> Vector2i:
	return Vector2i(int(ceil(canvas_px.x / cs - 0.001)), int(ceil(canvas_px.y / cs - 0.001)))


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cs


func cell_polygon(c: Vector2i) -> PackedVector2Array:
	var o := Vector2(c) * cs
	return PackedVector2Array([o, o + Vector2(cs, 0), o + Vector2(cs, cs), o + Vector2(0, cs)])


func point_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / cs)), int(floor(p.y / cs)))


const _N4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in _N4:
		var n := c + d
		if in_grid(n):
			out.append(n)
	return out


func inradius() -> float:
	return cs * 0.5


func cell_range_for_rect(r: Rect2) -> Rect2i:
	var a := Vector2i(int(floor(r.position.x / cs)) - 1, int(floor(r.position.y / cs)) - 1)
	var b := Vector2i(int(ceil(r.end.x / cs)) + 1, int(ceil(r.end.y / cs)) + 1)
	return Rect2i(a, b - a)


func rotation_step_deg() -> float:
	return 90.0


func snap_pivot(p: Vector2) -> Vector2:
	# Rotating 90 degrees about either a cell center or a grid vertex maps
	# cells onto cells; pick whichever is closer.
	var center := cell_center(point_to_cell(p))
	var vertex := (p / cs).round() * cs
	return center if p.distance_to(center) <= p.distance_to(vertex) else vertex


func glsl() -> String:
	return """
ivec2 TL_cell(vec2 p, float cs, vec4 tp) { return ivec2(floor(p / cs)); }
vec2 TL_center(ivec2 c, float cs, vec4 tp) { return (vec2(c) + 0.5) * cs; }
float TL_inradius(float cs) { return cs * 0.5; }
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) {
	vec2 q = abs(p - TL_center(c, cs, tp));
	vec2 b = vec2(max(cs * 0.5 - inset - rnd, 0.0));
	vec2 d = q - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - rnd;
}
"""
