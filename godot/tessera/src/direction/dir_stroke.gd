class_name DirStroke
extends RefCounted
## Direction-layer strokes. A stroke is a Dictionary:
##   type:     "path" (arrow / freehand / bezier), "swirl_cw", "swirl_ccw",
##             "radial_out", "radial_in"
##   kind:     how it was drawn: "arrow", "curve", "bezier", "field"
##   points:   PackedVector2Array in canvas px. Bezier strokes store
##             [a0, out0, in1, a1, out1, in2, a2, ...] (3n+1 points).
##             Swirl / radial store [center, rim].
##   radius:   influence radius px (0 = unlimited)
##   strength: weight of this stroke in the blended field

const TYPES := ["path", "swirl_cw", "swirl_ccw", "radial_out", "radial_in"]
const TYPE_NAMES := ["Path (follow stroke)", "Swirl clockwise", "Swirl counter-clockwise", "Radial out (explode)", "Radial in (attract)"]
const DEFAULT_SETTINGS := {
	"smoothing": 2.0,        # cells
	"default_on": false,
	"default_angle": 0.0,    # degrees
	"field_display": 1,      # 0 hidden, 1 arrows, 2 streamlines
	"new_type": 0,
	"new_radius": 0.0,       # cells, 0 = unlimited
	"new_strength": 1.0,
}


static func make(kind: String, type: String, pts: PackedVector2Array, radius: float, strength: float) -> Dictionary:
	return {"kind": kind, "type": type, "points": pts, "radius": radius, "strength": strength}


static func is_field_type(s: Dictionary) -> bool:
	return s.type != "path"


## Polyline for drawing / hit-testing / the field (Bezier flattened with a
## step count chosen by the caller: zoom for display, fixed for the field).
static func polyline(s: Dictionary, bezier_steps := 16) -> PackedVector2Array:
	var pts: PackedVector2Array = s.points
	if s.get("kind", "") != "bezier" or pts.size() < 4:
		return pts
	var out := PackedVector2Array()
	var i := 0
	while i + 3 < pts.size():
		var a := pts[i]
		var b := pts[i + 1]
		var c := pts[i + 2]
		var d := pts[i + 3]
		for k in bezier_steps:
			var t := float(k) / bezier_steps
			out.append(a.bezier_interpolate(b, c, d, t))
		i += 3
	out.append(pts[pts.size() - 1])
	return out


static func reversed(s: Dictionary) -> Dictionary:
	var r := s.duplicate(true)
	var pts: PackedVector2Array = s.points
	if is_field_type(s):
		var flip := {"swirl_cw": "swirl_ccw", "swirl_ccw": "swirl_cw", "radial_out": "radial_in", "radial_in": "radial_out"}
		r.type = flip[s.type]
		return r
	var rp := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		rp.append(pts[i])
	r.points = rp
	return r


static func distance_to(s: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = s.points
	if is_field_type(s):
		var rr := pts[0].distance_to(pts[1]) if pts.size() > 1 else 0.0
		return minf(absf(p.distance_to(pts[0]) - rr), p.distance_to(pts[0]))
	var pl := polyline(s)
	var best := INF
	for i in range(pl.size() - 1):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pl[i], pl[i + 1]).distance_to(p))
	return best


## Segment table for the field kernel: per segment 3 vec4:
## (a.xy, b.xy), (radius, strength, type, 0), (center.xy, 0, 0).
static func field_segments(strokes: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for s in strokes:
		var t: int = TYPES.find(s.type)
		var pts: PackedVector2Array = s.points
		if pts.size() < 2:
			continue
		if t > 0:
			var rr := pts[0].distance_to(pts[1])
			out.append_array([pts[0].x, pts[0].y, pts[1].x, pts[1].y, maxf(float(s.radius), rr), float(s.strength), t, 0.0, pts[0].x, pts[0].y, 0.0, 0.0])
			continue
		var pl := polyline(s)
		for i in range(pl.size() - 1):
			out.append_array([pl[i].x, pl[i].y, pl[i + 1].x, pl[i + 1].y, float(s.radius), float(s.strength), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	return out


# ---- direction presets ---------------------------------------------------------

const PRESETS := ["Uniform direction", "Vortex", "Radial burst", "Wave", "Turbulence"]


static func preset(name_: String, canvas: Vector2, seed_ := 1) -> Array:
	var c := canvas * 0.5
	var r := minf(canvas.x, canvas.y)
	match name_:
		"Uniform direction":
			var out: Array = []
			for k in 5:
				var y := canvas.y * (k + 0.5) / 5.0
				out.append(make("arrow", "path", PackedVector2Array([Vector2(canvas.x * 0.1, y), Vector2(canvas.x * 0.9, y)]), 0.0, 1.0))
			return out
		"Vortex":
			return [make("field", "swirl_cw", PackedVector2Array([c, c + Vector2(r * 0.45, 0)]), r * 0.7, 1.0)]
		"Radial burst":
			return [make("field", "radial_out", PackedVector2Array([c, c + Vector2(r * 0.4, 0)]), r * 0.8, 1.0)]
		"Wave":
			var out2: Array = []
			for k in 4:
				var pts := PackedVector2Array()
				var y0 := canvas.y * (k + 0.5) / 4.0
				for i in 33:
					var x := canvas.x * i / 32.0
					pts.append(Vector2(x, y0 + sin(x / canvas.x * TAU * 2.0) * canvas.y * 0.06))
				out2.append(make("curve", "path", pts, 0.0, 1.0))
			return out2
		"Turbulence":
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_
			var out3: Array = []
			for k in 9:
				var p := Vector2(rng.randf(), rng.randf()) * canvas
				var t: String = ["swirl_cw", "swirl_ccw"][k % 2]
				out3.append(make("field", t, PackedVector2Array([p, p + Vector2(r * 0.12, 0)]), r * 0.3, rng.randf_range(0.5, 1.0)))
			return out3
	return []


# ---- serialisation helpers --------------------------------------------------------

static func to_json(s: Dictionary) -> Dictionary:
	var flat: Array = []
	for v in s.points:
		flat.append_array([v.x, v.y])
	return {"kind": s.get("kind", "curve"), "type": s.type, "points": flat, "radius": s.radius, "strength": s.strength}


static func from_json(d: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	var flat: Array = d.get("points", [])
	for i in range(0, flat.size() - 1, 2):
		pts.append(Vector2(flat[i], flat[i + 1]))
	return make(d.get("kind", "curve"), d.get("type", "path"), pts, float(d.get("radius", 0.0)), float(d.get("strength", 1.0)))
