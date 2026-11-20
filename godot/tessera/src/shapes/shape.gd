class_name Shape
extends RefCounted
## Custom shapes (Shape Editor). Plain dictionaries so they save as JSON and
## can be embedded in projects and libraries.
##
## Tiling shape (always tiles by construction):
##   {id, name, kind: "tiling", base, corners: [Vector2 x k/2], edges: [edge x k/2]}
##   The tile is centrally symmetric: corner i + k/2 = -corner i. Edge i runs
##   corner i -> corner i+1; only edges 0..k/2-1 are stored. Each is a cubic
##   chain in its own edge frame (x = along the edge 0..1, y = perpendicular,
##   in edge lengths): [out(C_i), in(A1), A1, out(A1), ..., in(C_i+1)]
##   (3m+2 points for m interior anchors) plus "smooth": [bool x m].
##   Edge i + k/2 is edge i reversed and translated by T_i = -(C_i + C_i+1),
##   so opposite edges are always exact copies. Units: cells.
## Stamp shape (free):
##   {id, name, kind: "stamp", paths: [{points: [3n+1 absolute chain], closed}]}
##   in a unit box centered on the origin (fit inside the tile when drawn).

const BASES := ["square", "rectangle", "parallelogram", "hexagon"]


static func new_id() -> String:
	return "%x%x" % [Time.get_ticks_usec(), randi()]


static func straight_edge() -> Dictionary:
	return {"chain": [Vector2(1.0 / 3.0, 0), Vector2(2.0 / 3.0, 0)], "smooth": []}


static func new_tiling(base: String, name_ := "") -> Dictionary:
	var corners: Array = []
	match base:
		"rectangle":
			corners = [Vector2(-0.75, -0.5), Vector2(0.75, -0.5)]
		"parallelogram":
			corners = [Vector2(-0.75, -0.5), Vector2(0.25, -0.5)]
		"hexagon":
			var r := 1.0 / sqrt(3.0)
			for i in 3:
				var a := deg_to_rad(60.0 * i - 150.0)
				corners.append(Vector2(cos(a), sin(a)) * r)
		_:
			corners = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5)]
	var edges: Array = []
	for i in corners.size():
		edges.append(straight_edge())
	return {"id": new_id(), "name": name_ if name_ != "" else base.capitalize(), "kind": "tiling", "base": base,
		"corners": corners, "edges": edges}


static func new_stamp(name_ := "Stamp") -> Dictionary:
	# A rounded diamond to start from.
	var pts := [Vector2(0, -0.45), Vector2(0.2, -0.3), Vector2(0.3, -0.2), Vector2(0.45, 0),
		Vector2(0.3, 0.2), Vector2(0.2, 0.3), Vector2(0, 0.45), Vector2(-0.2, 0.3), Vector2(-0.3, 0.2),
		Vector2(-0.45, 0), Vector2(-0.3, -0.2), Vector2(-0.2, -0.3), Vector2(0, -0.45)]
	return {"id": new_id(), "name": name_, "kind": "stamp", "paths": [{"points": pts, "closed": true}]}


# ---- tiling geometry ------------------------------------------------------------

static func corner_count(s: Dictionary) -> int:
	return s.corners.size() * 2


static func corner(s: Dictionary, i: int) -> Vector2:
	var h: int = s.corners.size()
	i = posmod(i, h * 2)
	return s.corners[i] if i < h else -(s.corners[i - h] as Vector2)


static func translation(s: Dictionary, i: int) -> Vector2:
	return -(corner(s, i) + corner(s, i + 1))


## Edge frame: point (x along, y perpendicular) -> shape coordinates.
static func edge_point(s: Dictionary, i: int, local: Vector2) -> Vector2:
	var a := corner(s, i)
	var b := corner(s, i + 1)
	var d := b - a
	return a + d * local.x + Vector2(-d.y, d.x) * local.y


static func edge_local(s: Dictionary, i: int, p: Vector2) -> Vector2:
	var a := corner(s, i)
	var d := corner(s, i + 1) - a
	var l2 := maxf(d.length_squared(), 1e-9)
	var r := p - a
	return Vector2(r.dot(d) / l2, r.dot(Vector2(-d.y, d.x)) / l2)


## Absolute cubic chain (3m+4 points incl. both corners) of any edge 0..k-1.
static func edge_chain(s: Dictionary, i: int) -> PackedVector2Array:
	var h: int = s.corners.size()
	i = posmod(i, h * 2)
	var base := i if i < h else i - h
	var e: Dictionary = s.edges[base]
	var pts := PackedVector2Array([corner(s, base)])
	for loc in e.chain:
		pts.append(edge_point(s, base, loc))
	pts.append(corner(s, base + 1))
	if i < h:
		return pts
	# Paired edge: the stored edge reversed and translated.
	var t := translation(s, base)
	var out := PackedVector2Array()
	for k in range(pts.size() - 1, -1, -1):
		out.append(pts[k] + t)
	return out


## Whole outline as one closed cubic chain (3n+1 points, last == first).
static func outline_chain(s: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in corner_count(s):
		var e := edge_chain(s, i)
		if i == 0:
			out.append_array(e)
		else:
			out.append_array(e.slice(1))
	return out


static func flatten_chain(pts: PackedVector2Array, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i + 3 < pts.size():
		for k in steps:
			out.append(pts[i].bezier_interpolate(pts[i + 1], pts[i + 2], pts[i + 3], float(k) / steps))
		i += 3
	return out


## Flattened outline polygon (cells). Straight segments stay one segment.
static func polygon(s: Dictionary, steps := 8) -> PackedVector2Array:
	var ch := outline_chain(s)
	var out := PackedVector2Array()
	var i := 0
	while i + 3 < ch.size():
		var a := ch[i]
		var b := ch[i + 1]
		var c := ch[i + 2]
		var d := ch[i + 3]
		var straight := absf((b - a).cross(d - a)) < 1e-6 and absf((c - a).cross(d - a)) < 1e-6
		var n := 1 if straight else steps
		for k in n:
			var q := a.bezier_interpolate(b, c, d, float(k) / n)
			if out.is_empty() or out[out.size() - 1].distance_squared_to(q) > 1e-10:
				out.append(q)
		i += 3
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) < 1e-10:
		out.remove_at(out.size() - 1)
	return out


## Lattice basis (cells): u = T_0, v = T_1.
static func basis(s: Dictionary) -> Array:
	return [translation(s, 0), translation(s, 1)]


## Lattice offsets (in basis coordinates) of every edge neighbour.
static func neighbor_offsets(s: Dictionary) -> Array:
	var b := basis(s)
	var u: Vector2 = b[0]
	var v: Vector2 = b[1]
	var det := u.x * v.y - u.y * v.x
	var out: Array = []
	for i in s.corners.size():
		var t := translation(s, i)
		var a := (t.x * v.y - t.y * v.x) / det
		var c := (u.x * t.y - u.y * t.x) / det
		var o := Vector2i(roundi(a), roundi(c))
		out.append(o)
		out.append(-o)
	return out


# ---- editing helpers (keep pairing by construction) -----------------------------

## Insert an anchor on edge `i` (any edge; paired edges map to their base).
static func add_edge_point(s: Dictionary, i: int, p: Vector2) -> void:
	var h: int = s.corners.size()
	i = posmod(i, h * 2)
	var base := i
	if i >= h:
		base = i - h
		p -= translation(s, base)
	var loc := edge_local(s, base, p)
	var e: Dictionary = s.edges[base]
	var chain: Array = e.chain
	# anchors are at indices 2, 5, 8... ; find insertion by x.
	var anchors: Array = []
	for k in range(2, chain.size() - 1, 3):
		anchors.append(chain[k].x)
	var slot := 0
	while slot < anchors.size() and anchors[slot] < loc.x:
		slot += 1
	var prev_x: float = 0.0 if slot == 0 else anchors[slot - 1]
	var next_x: float = 1.0 if slot >= anchors.size() else anchors[slot]
	var inh := Vector2(loc.x - (loc.x - prev_x) / 3.0, loc.y)
	var outh := Vector2(loc.x + (next_x - loc.x) / 3.0, loc.y)
	# Layout: [out(C), in(A0), A0, out(A0), in(A1), ...]; anchor k sits at
	# 2 + 3k, so a new anchor at `slot` starts at 1 + 3*slot.
	var at := 1 + 3 * slot
	chain.insert(at, outh)
	chain.insert(at, loc)
	chain.insert(at, inh)
	(e.smooth as Array).insert(slot, false)


## Remove anchor number `a` (0-based among the edge's interior anchors).
static func remove_edge_anchor(s: Dictionary, base: int, a: int) -> void:
	var e: Dictionary = s.edges[base]
	var idx := 2 + a * 3
	var chain: Array = e.chain
	if idx >= chain.size() - 1:
		return
	chain.remove_at(idx + 1)
	chain.remove_at(idx)
	chain.remove_at(idx - 1)
	(e.smooth as Array).remove_at(a)


# ---- built-in starting shapes ----------------------------------------------------

static func _edge(points: Array, smooth: Array) -> Dictionary:
	return {"chain": points, "smooth": smooth}


static func builtin(name_: String) -> Dictionary:
	match name_:
		"Chevron":
			var s := new_tiling("square", "Chevron")
			# Top edge gets a V; the bottom follows automatically.
			s.edges[0] = _edge([Vector2(0.17, 0.0), Vector2(0.33, 0.25), Vector2(0.5, 0.25), Vector2(0.67, 0.25), Vector2(0.83, 0.0)], [false])
			return s
		"Puzzle piece":
			var p := new_tiling("square", "Puzzle piece")
			var knob := [Vector2(0.2, 0), Vector2(0.38, 0), Vector2(0.38, 0.05), Vector2(0.36, 0.12), Vector2(0.3, -0.2),
				Vector2(0.5, -0.24), Vector2(0.7, -0.2), Vector2(0.64, 0.12), Vector2(0.62, 0.05), Vector2(0.62, 0), Vector2(0.8, 0)]
			p.edges[0] = _edge(knob, [true, true, true])
			var knob2 := []
			for v in knob:
				knob2.append(Vector2(v.x, -v.y))
			p.edges[1] = _edge(knob2, [true, true, true])
			return p
		"Fish scale":
			var f := new_tiling("square", "Fish scale")
			f.edges[0] = _edge([Vector2(0.1, -0.35), Vector2(0.9, -0.35)], [])
			return f
		"Lizard interlock":
			var h := new_tiling("hexagon", "Lizard interlock")
			h.edges[0] = _edge([Vector2(0.1, 0.25), Vector2(0.35, 0.3), Vector2(0.5, 0.0), Vector2(0.65, -0.3), Vector2(0.9, -0.25)], [true])
			h.edges[1] = _edge([Vector2(0.2, -0.2), Vector2(0.4, -0.25), Vector2(0.55, 0.05), Vector2(0.7, 0.3), Vector2(0.85, 0.15)], [true])
			h.edges[2] = _edge([Vector2(0.15, 0.2), Vector2(0.45, 0.25), Vector2(0.5, 0.0), Vector2(0.55, -0.25), Vector2(0.85, -0.2)], [true])
			return h
	return new_tiling(name_.to_lower())


const BUILTINS := ["Square", "Rectangle", "Parallelogram", "Hexagon", "Chevron", "Puzzle piece", "Fish scale", "Lizard interlock"]


# ---- JSON -----------------------------------------------------------------------

static func _v(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append([v.x, v.y])
	return out


static func _p(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(Vector2(v[0], v[1]))
	return out


static func to_json(s: Dictionary) -> Dictionary:
	var d := {"id": s.id, "name": s.name, "kind": s.kind, "format_version": 1}
	if s.kind == "tiling":
		d.base = s.base
		d.corners = _v(s.corners)
		d.edges = s.edges.map(func(e): return {"chain": _v(e.chain), "smooth": e.smooth.duplicate()})
	else:
		d.paths = s.paths.map(func(pa): return {"points": _v(pa.points), "closed": pa.get("closed", true)})
	return d


static func from_json(d: Dictionary) -> Dictionary:
	var s := {"id": str(d.get("id", new_id())), "name": d.get("name", "Shape"), "kind": d.get("kind", "stamp")}
	if s.kind == "tiling":
		s.base = d.get("base", "square")
		s.corners = _p(d.get("corners", []))
		s.edges = d.get("edges", []).map(func(e): return {"chain": _p(e.chain), "smooth": e.get("smooth", []).duplicate()})
	else:
		s.paths = d.get("paths", []).map(func(pa): return {"points": _p(pa.points), "closed": pa.get("closed", true)})
	return s


static func duplicate_shape(s: Dictionary) -> Dictionary:
	return from_json(to_json(s))


## Signed distance field of a stamp shape (RF image, unit box [-0.5, 0.5]
## mapped to the texture; negative inside, even-odd fill so holes work).
## Computed on the GPU from the flattened outline segments.
static func stamp_sdf(s: Dictionary, res := 128) -> Image:
	var segs := PackedFloat32Array()
	for p in s.get("paths", []):
		var pts := PackedVector2Array(p.points)
		var flat := flatten_chain(pts, 12)
		if flat.size() < 2:
			continue
		flat.append(flat[0])
		for i in range(flat.size() - 1):
			segs.append_array([flat[i].x, flat[i].y, flat[i + 1].x, flat[i + 1].y])
	var n := segs.size() / 4
	var out := PackedByteArray()
	out.resize(res * res * 4)
	if n == 0:
		var far := PackedFloat32Array()
		far.resize(res * res)
		far.fill(1.0)
		return Image.create_from_data(res, res, false, Image.FORMAT_RF, far.to_byte_array())
	var code := """#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer Segs { vec4 s[]; } segs;
layout(set = 0, binding = 1, std430) restrict writeonly buffer Out { float v[]; } outb;
layout(push_constant, std430) uniform P { int res; int n; } pc;
void main() {
	ivec2 g = ivec2(gl_GlobalInvocationID.xy);
	if (g.x >= pc.res || g.y >= pc.res) { return; }
	vec2 q = (vec2(g) + 0.5) / float(pc.res) - 0.5;
	float d = 1e9;
	bool inside = false;
	for (int i = 0; i < pc.n; i++) {
		vec2 a = segs.s[i].xy; vec2 b = segs.s[i].zw;
		vec2 e = b - a; vec2 w = q - a;
		vec2 h = w - e * clamp(dot(w, e) / max(dot(e, e), 1e-12), 0.0, 1.0);
		d = min(d, dot(h, h));
		if (((a.y > q.y) != (b.y > q.y)) && (q.x < e.x * (q.y - a.y) / (b.y - a.y) + a.x)) { inside = !inside; }
	}
	outb.v[g.y * pc.res + g.x] = sqrt(d) * (inside ? -1.0 : 1.0);
}
"""
	var res_ := Gpu.run("stamp_sdf", code, [segs.to_byte_array(), out], Gpu.push().i(res).i(n).bytes, Vector3i(ceili(res / 8.0), ceili(res / 8.0), 1), [1])
	var data: PackedByteArray = res_[0] if not res_.is_empty() else out
	data.resize(res * res * 4)
	return Image.create_from_data(res, res, false, Image.FORMAT_RF, data)
