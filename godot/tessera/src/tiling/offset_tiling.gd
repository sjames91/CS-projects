class_name OffsetTiling
extends Tiling
## Offset (Layer Settings section 5) as a decorator around any tiling. It is
## the only place grid shifting happens. Because it implements the same
## interface (and wraps the GLSL snippet the same way), tools, fill,
## selection and rendering need no changes and clicks land on the shifted
## cells exactly as drawn.
##
## Cells keep their coordinates; the grid is drawn shifted by -amount*cs.
## The wrapped tiling covers one extra cell of canvas so no gap appears.

enum Mode { NONE, HALF_X, HALF_Y, HALF_BOTH, BRICK_ROWS, BRICK_COLS }
const MODE_NAMES := ["None", "Half X", "Half Y", "Half both", "Brick rows", "Brick columns"]

var base: Tiling
var mode := Mode.NONE
var shift := 0.0  # px


static func wrap(b: Tiling, cell_size: float, canvas_size_px: Vector2, offset_mode: int, amount: float) -> Tiling:
	var t := OffsetTiling.new()
	t.base = b
	t.mode = offset_mode
	t.shift = clampf(amount, 0.0, 1.0) * cell_size
	t.cs = cell_size
	t.canvas_px = canvas_size_px
	t.params = b.params
	t.grid = b.grid
	return t


## Which offset modes make sense for a tiling (brick only if not staggered).
static func modes_for(b: Tiling) -> Array:
	var out := [Mode.NONE, Mode.HALF_X, Mode.HALF_Y, Mode.HALF_BOTH]
	if not b.staggered_rows():
		out.append(Mode.BRICK_ROWS)
	if not b.staggered_cols():
		out.append(Mode.BRICK_COLS)
	return out


func id() -> String:
	return base.id()


func display_name() -> String:
	return base.display_name() + " (" + MODE_NAMES[mode] + ")"


func param_defs() -> Array:
	return base.param_defs()


func shader_key() -> String:
	return "%s+off%d" % [base.shader_key(), mode]


func offset_of(c: Vector2i) -> Vector2:
	match mode:
		Mode.HALF_X:
			return Vector2(-shift, 0)
		Mode.HALF_Y:
			return Vector2(0, -shift)
		Mode.HALF_BOTH:
			return Vector2(-shift, -shift)
		Mode.BRICK_ROWS:
			return Vector2(-shift, 0) if (c.y & 1) == 1 else Vector2.ZERO
		Mode.BRICK_COLS:
			return Vector2(0, -shift) if (c.x & 1) == 1 else Vector2.ZERO
	return Vector2.ZERO


func cell_center(c: Vector2i) -> Vector2:
	return base.cell_center(c) + offset_of(c)


func cell_polygon(c: Vector2i) -> PackedVector2Array:
	var o := offset_of(c)
	var out := PackedVector2Array()
	for v in base.cell_polygon(c):
		out.append(v + o)
	return out


func point_to_cell(p: Vector2) -> Vector2i:
	match mode:
		Mode.HALF_X, Mode.HALF_Y, Mode.HALF_BOTH:
			return base.point_to_cell(p - offset_of(Vector2i.ZERO))
		Mode.BRICK_ROWS:
			var c0 := base.point_to_cell(p)
			return base.point_to_cell(p + Vector2(shift, 0)) if (c0.y & 1) == 1 else c0
		Mode.BRICK_COLS:
			var c1 := base.point_to_cell(p)
			return base.point_to_cell(p + Vector2(0, shift)) if (c1.x & 1) == 1 else c1
	return base.point_to_cell(p)


## Edge neighbours found geometrically (brick offsets change adjacency):
## probe just outside several points along every edge of the cell.
func neighbors(c: Vector2i) -> Array[Vector2i]:
	if mode in [Mode.NONE, Mode.HALF_X, Mode.HALF_Y, Mode.HALF_BOTH]:
		return base.neighbors(c)
	var out: Array[Vector2i] = []
	var poly := cell_polygon(c)
	var ctr := cell_center(c)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for t in [0.2, 0.5, 0.8]:
			var m: Vector2 = a.lerp(b, t)
			var n := point_to_cell(m + (m - ctr).normalized() * 0.25)
			if n != c and in_grid(n) and not out.has(n):
				out.append(n)
	return out


func inradius() -> float:
	return base.inradius()


func cell_range_for_rect(r: Rect2) -> Rect2i:
	return base.cell_range_for_rect(r.grow(shift + 1.0))


func rotation_step_deg() -> float:
	return 180.0 if mode in [Mode.BRICK_ROWS, Mode.BRICK_COLS] else base.rotation_step_deg()


func snap_pivot(p: Vector2) -> Vector2:
	var c := point_to_cell(p)
	return cell_center(c) if in_grid(c) else p


func staggered_rows() -> bool:
	return base.staggered_rows() or mode == Mode.BRICK_ROWS


func staggered_cols() -> bool:
	return base.staggered_cols() or mode == Mode.BRICK_COLS


func glsl_params() -> Vector4:
	var b := base.glsl_params()
	return Vector4(b.x, b.y, 0.0, shift)


func glsl() -> String:
	var off := ""
	var cell := ""
	match mode:
		Mode.HALF_X:
			off = "return vec2(-tp.w, 0.0);"
			cell = "return TL_B_cell(p + vec2(tp.w, 0.0), cs, tp);"
		Mode.HALF_Y:
			off = "return vec2(0.0, -tp.w);"
			cell = "return TL_B_cell(p + vec2(0.0, tp.w), cs, tp);"
		Mode.HALF_BOTH:
			off = "return vec2(-tp.w);"
			cell = "return TL_B_cell(p + vec2(tp.w), cs, tp);"
		Mode.BRICK_ROWS:
			off = "return (c.y & 1) == 1 ? vec2(-tp.w, 0.0) : vec2(0.0);"
			cell = "ivec2 c0 = TL_B_cell(p, cs, tp); return (c0.y & 1) == 1 ? TL_B_cell(p + vec2(tp.w, 0.0), cs, tp) : c0;"
		Mode.BRICK_COLS:
			off = "return (c.x & 1) == 1 ? vec2(0.0, -tp.w) : vec2(0.0);"
			cell = "ivec2 c0 = TL_B_cell(p, cs, tp); return (c0.x & 1) == 1 ? TL_B_cell(p + vec2(0.0, tp.w), cs, tp) : c0;"
		_:
			off = "return vec2(0.0);"
			cell = "return TL_B_cell(p, cs, tp);"
	return base.glsl_prefixed("TL_B_") + """
vec2 TL_off(ivec2 c, vec4 tp) { %s }
ivec2 TL_cell(vec2 p, float cs, vec4 tp) { %s }
vec2 TL_center(ivec2 c, float cs, vec4 tp) { return TL_B_center(c, cs, tp) + TL_off(c, tp); }
float TL_inradius(float cs) { return TL_B_inradius(cs); }
float TL_sdf(vec2 p, ivec2 c, float cs, vec4 tp, float inset, float rnd) { return TL_B_sdf(p - TL_off(c, tp), c, cs, tp, inset, rnd); }
""" % [off, cell]
