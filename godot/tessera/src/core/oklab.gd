class_name OkLab
extends RefCounted
## OKLab conversions. All colour matching in the app uses these (GDScript for
## the few-hundred-entry palette work, the same maths in GLSL on the GPU).

const GLSL := """
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 linear_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 rgb_to_oklab(vec3 srgb) {
	vec3 c = srgb_to_linear(srgb);
	float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
	l = pow(max(l, 0.0), 1.0 / 3.0); m = pow(max(m, 0.0), 1.0 / 3.0); s = pow(max(s, 0.0), 1.0 / 3.0);
	return vec3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}
vec3 oklab_to_rgb(vec3 lab) {
	float l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
	float m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
	float s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
	l = l * l * l; m = m * m * m; s = s * s * s;
	return linear_to_srgb(vec3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s));
}
"""


const BAYER_GLSL := """
float bayer8(ivec2 p) {
	int x = p.x & 7;
	int y = p.y & 7;
	int xy = x ^ y;
	int v = ((xy & 1) << 5) | ((x & 1) << 4) | ((xy & 2) << 2) | ((x & 2) << 1) | ((xy & 4) >> 1) | ((x & 4) >> 2);
	return (float(v) + 0.5) / 64.0;
}
"""

## Shared nearest-palette (OKLab) logic, used by the export kernel and by the
## preview's Palette Lock shader so both give the same answer.
const SNAP_GLSL := """
vec3 snap_pick(vec3 lab, ivec2 px, int count, bool dither, float strength) {
	int ia = 0; int ib = 0;
	float da = 1e9; float db = 1e9;
	for (int i = 0; i < count; i++) {
		vec3 d = lab - PAL_LAB(i);
		float dd = dot(d, d);
		if (dd < da) { db = da; ib = ia; da = dd; ia = i; }
		else if (dd < db) { db = dd; ib = i; }
	}
	if (!dither || count < 2) { return PAL_RGB(ia); }
	vec3 a = PAL_LAB(ia);
	vec3 b = PAL_LAB(ib);
	vec3 ab = b - a;
	float f = clamp(dot(lab - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
	return (bayer8(px) < f * strength * 2.0) ? PAL_RGB(ib) : PAL_RGB(ia);
}
"""


static func _to_lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _to_srgb(c: float) -> float:
	c = maxf(c, 0.0)
	return c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


static func from_color(col: Color) -> Vector3:
	var r := _to_lin(col.r)
	var g := _to_lin(col.g)
	var b := _to_lin(col.b)
	var l := pow(maxf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 0.0), 1.0 / 3.0)
	var m := pow(maxf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 0.0), 1.0 / 3.0)
	var s := pow(maxf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 0.0), 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


static func to_color(lab: Vector3, alpha := 1.0) -> Color:
	var l := lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
	var m := lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
	var s := lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
	l = l * l * l
	m = m * m * m
	s = s * s * s
	return Color(
		clampf(_to_srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s), 0, 1),
		clampf(_to_srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s), 0, 1),
		clampf(_to_srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), 0, 1), alpha)


static func distance(a: Color, b: Color) -> float:
	return from_color(a).distance_to(from_color(b))


static func lightness(c: Color) -> float:
	return from_color(c).x


## Sort colours into ramps: low-chroma colours form a grey ramp, the rest are
## grouped by hue bucket, every ramp ordered dark to light.
static func sort_into_ramps(colors: PackedColorArray, hue_buckets := 8) -> PackedColorArray:
	var greys: Array = []
	var buckets: Array = []
	for i in hue_buckets:
		buckets.append([])
	for c in colors:
		var lab := from_color(c)
		var chroma := Vector2(lab.y, lab.z).length()
		if chroma < 0.03:
			greys.append([lab.x, c])
		else:
			var hue := fposmod(atan2(lab.z, lab.y), TAU)
			var b := int(hue / TAU * hue_buckets) % hue_buckets
			buckets[b].append([lab.x, c])
	var out := PackedColorArray()
	var by_l := func(a, b): return a[0] < b[0]
	greys.sort_custom(by_l)
	for g in greys:
		out.append(g[1])
	for b in buckets:
		b.sort_custom(by_l)
		for e in b:
			out.append(e[1])
	return out
