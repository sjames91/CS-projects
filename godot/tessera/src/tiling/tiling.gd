class_name Tiling
extends RefCounted
## The one interface every tiling implements.
##
## Cells are stored in a rectangular grid of (col, row) coordinates that is
## private to each tiling. Everything outside the tiling's own file (tools,
## selection, fill, rendering, resampling) goes through these methods and the
## GLSL snippet returned by glsl(); nothing else knows which shape it is.
##
## GLSL contract (prefix TL_ is replaced per use, so two tilings can live in
## one shader):
##   ivec2 TL_cell(vec2 p, float cs, vec4 tp)              canvas px -> cell
##   vec2  TL_center(ivec2 c, float cs, vec4 tp)           cell -> center px
##   float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd)
##         signed distance (px, negative inside) to the cell's shape after
##         shrinking it by `inset` and rounding its corners by `rnd`.
##   float TL_inradius(float cs)
## The snippet must only use math (no textures) so it also compiles inside
## compute shaders. tp is glsl_params(): tp.xy belong to the tiling itself,
## tp.zw are reserved for the Offset decorator. Anything else a snippet
## needs is baked in as constants, and shader_key() changes with it.

const INVALID := Vector2i(-2147483648, -2147483648)

var cs: float = 8.0
var canvas_px: Vector2 = Vector2(512, 512)
var params: Dictionary = {}
var grid: Vector2i = Vector2i.ZERO


func setup(cell_size: float, canvas_size_px: Vector2, tiling_params: Dictionary) -> Tiling:
	cs = cell_size
	canvas_px = canvas_size_px
	params = tiling_params.duplicate()
	grid = compute_grid()
	_on_setup()
	return self


func _on_setup() -> void:
	pass


# ---- identity -------------------------------------------------------------

func id() -> String:
	return "base"


func display_name() -> String:
	return "Base"


## Parameters the Layer Settings panel shows for this tiling:
## [{key, label, min, max, step, default}]
func param_defs() -> Array:
	return []


func param(key: String, fallback: Variant) -> Variant:
	return params.get(key, fallback)


# ---- geometry -------------------------------------------------------------

func compute_grid() -> Vector2i:
	return Vector2i.ONE


func cell_count() -> int:
	return grid.x * grid.y


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid.x and c.y < grid.y


func index(c: Vector2i) -> int:
	return c.y * grid.x + c.x


func cell_of_index(i: int) -> Vector2i:
	return Vector2i(i % grid.x, i / grid.x)


func cell_center(_c: Vector2i) -> Vector2:
	return Vector2.ZERO


func cell_polygon(_c: Vector2i) -> PackedVector2Array:
	return PackedVector2Array()


## Cell containing canvas point p (may be outside the grid; check in_grid).
func point_to_cell(_p: Vector2) -> Vector2i:
	return INVALID


## Edge-adjacent neighbours inside the grid (used by fill, wand, rounding).
func neighbors(_c: Vector2i) -> Array[Vector2i]:
	return []


## Distance from the center to the nearest edge, for a cell of this tiling.
func inradius() -> float:
	return cs * 0.5


## Conservative range of grid cells that could touch rect r (canvas px).
func cell_range_for_rect(_r: Rect2) -> Rect2i:
	return Rect2i(Vector2i.ZERO, grid)


# ---- symmetry -------------------------------------------------------------

## Smallest rotation (degrees) that maps the tiling onto itself.
func rotation_step_deg() -> float:
	return 90.0


func can_flip_h() -> bool:
	return true


func can_flip_v() -> bool:
	return true


## Nearest point about which rotation/flip steps map cells onto cells.
func snap_pivot(p: Vector2) -> Vector2:
	var c := point_to_cell(p)
	return cell_center(c) if c != INVALID else p


## Whether rows / columns are already staggered (Offset uses this).
func staggered_rows() -> bool:
	return false


func staggered_cols() -> bool:
	return false


# ---- GPU ------------------------------------------------------------------

func glsl() -> String:
	return ""


func glsl_params() -> Vector4:
	return Vector4.ZERO


## Shaders are cached by this key; it must change whenever glsl() does.
func shader_key() -> String:
	return id()


## Returns glsl() with the TL_ prefix replaced, e.g. "src_" / "dst_".
func glsl_prefixed(prefix: String) -> String:
	return glsl().replace("TL_", prefix)


# ---- generic helpers built only on the interface ---------------------------

func cells_in_rect(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var range_ := cell_range_for_rect(r).intersection(Rect2i(Vector2i.ZERO, grid))
	for y in range(range_.position.y, range_.end.y):
		for x in range(range_.position.x, range_.end.x):
			var c := Vector2i(x, y)
			if r.has_point(cell_center(c)):
				out.append(c)
	return out


func cells_in_polygon(poly: PackedVector2Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if poly.size() < 3:
		return out
	var bb := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		bb = bb.expand(v)
	var range_ := cell_range_for_rect(bb).intersection(Rect2i(Vector2i.ZERO, grid))
	for y in range(range_.position.y, range_.end.y):
		for x in range(range_.position.x, range_.end.x):
			var c := Vector2i(x, y)
			if Geometry2D.is_point_in_polygon(cell_center(c), poly):
				out.append(c)
	return out


func cells_in_ellipse(center: Vector2, radii: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rx: float = max(radii.x, 0.001)
	var ry: float = max(radii.y, 0.001)
	var range_ := cell_range_for_rect(Rect2(center - radii, radii * 2.0)).intersection(Rect2i(Vector2i.ZERO, grid))
	for y in range(range_.position.y, range_.end.y):
		for x in range(range_.position.x, range_.end.x):
			var c := Vector2i(x, y)
			var d := (cell_center(c) - center) / Vector2(rx, ry)
			if d.length_squared() <= 1.0:
				out.append(c)
	return out


func cells_in_disc(center: Vector2, radius: float) -> Array[Vector2i]:
	if radius <= cs * 0.5:
		var c := point_to_cell(center)
		var single: Array[Vector2i] = []
		if in_grid(c):
			single.append(c)
		return single
	return cells_in_ellipse(center, Vector2(radius, radius))


## Points sampled along a segment, close enough that no cell is skipped.
func sample_segment(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var step: float = max(inradius() * 0.5, 0.25)
	var n := int(ceil(a.distance_to(b) / step))
	for i in range(n + 1):
		pts.append(a.lerp(b, float(i) / float(max(n, 1))))
	return pts


func cells_on_segment(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for p in sample_segment(a, b):
		var c := point_to_cell(p)
		if in_grid(c) and not seen.has(c):
			seen[c] = true
			out.append(c)
	return out


## Remap a cell through a canvas-space transform (rotation/flip) using only
## centers and point lookup. Works for every tiling whose symmetry allows it.
func transform_cell(c: Vector2i, xf: Transform2D) -> Vector2i:
	return point_to_cell(xf * cell_center(c))
