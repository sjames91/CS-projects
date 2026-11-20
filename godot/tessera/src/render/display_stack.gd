class_name DisplayStack
extends RefCounted
## Global effects applied once to the final composited image, after all
## layers and before Palette Lock.

const DEFAULTS := {
	"curv_on": false, "curvature": 0.12,
	"vig_on": false, "vignette": 0.4,
	"bloom_on": false, "bloom_threshold": 0.6, "bloom_radius": 6.0, "bloom_intensity": 0.6,
	"chroma_on": false, "chroma": 1.5,
	"interlace_on": false, "interlace": 0.25,
	"noise_on": false, "noise": 0.08,
}

## Each preset sets the Display stack and suggests per-layer CRT features.
const PRESETS := {
	"Consumer TV": {
		"display": {"curv_on": true, "curvature": 0.14, "vig_on": true, "vignette": 0.45, "bloom_on": true, "bloom_threshold": 0.55, "bloom_radius": 6.0, "bloom_intensity": 0.5, "chroma_on": true, "chroma": 1.2, "interlace_on": true, "interlace": 0.15, "noise_on": true, "noise": 0.06},
		"crt": {"scan_on": true, "scan_thickness": 0.45, "scan_dark": 0.45, "scan_spacing": 3.0, "mask_on": true, "mask_type": 1, "mask_strength": 0.45, "mask_size": 1.0, "beam_on": false, "bleed_on": true, "bleed": 0.35},
	},
	"Arcade monitor": {
		"display": {"curv_on": true, "curvature": 0.08, "vig_on": true, "vignette": 0.3, "bloom_on": true, "bloom_threshold": 0.5, "bloom_radius": 8.0, "bloom_intensity": 0.8, "chroma_on": false, "interlace_on": false, "noise_on": false},
		"crt": {"scan_on": true, "scan_thickness": 0.5, "scan_dark": 0.6, "scan_spacing": 4.0, "mask_on": true, "mask_type": 2, "mask_strength": 0.5, "mask_size": 1.0, "beam_on": true, "beam_amount": 0.6, "bleed_on": false},
	},
	"PVM monitor": {
		"display": {"curv_on": true, "curvature": 0.03, "vig_on": true, "vignette": 0.15, "bloom_on": true, "bloom_threshold": 0.75, "bloom_radius": 3.0, "bloom_intensity": 0.3, "chroma_on": false, "interlace_on": false, "noise_on": false},
		"crt": {"scan_on": true, "scan_thickness": 0.35, "scan_dark": 0.7, "scan_spacing": 3.0, "mask_on": true, "mask_type": 0, "mask_strength": 0.6, "mask_size": 1.0, "beam_on": true, "beam_amount": 0.4, "bleed_on": false},
	},
	"Handheld LCD": {
		"display": {"curv_on": false, "vig_on": false, "bloom_on": false, "chroma_on": false, "interlace_on": false, "noise_on": true, "noise": 0.03},
		"crt": {"scan_on": false, "mask_on": false, "beam_on": false, "bleed_on": false},
	},
}


static func settings(p: ProjectData) -> Dictionary:
	var d := DEFAULTS.duplicate()
	d.merge(p.display, true)
	return d


static func any_on(p: ProjectData) -> bool:
	var d := settings(p)
	for k in ["curv_on", "vig_on", "bloom_on", "chroma_on", "interlace_on", "noise_on"]:
		if d[k]:
			return true
	return false


static func is_animated(p: ProjectData) -> bool:
	var d := settings(p)
	return d.interlace_on or d.noise_on


static var _shader: Shader


static func shader() -> Shader:
	if _shader:
		return _shader
	_shader = Shader.new()
	_shader.code = """shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D pre_tex : filter_linear, repeat_disable;
uniform vec2 view_size = vec2(512.0);
uniform float zoom = 1.0;
uniform vec2 pan = vec2(0.0);
uniform float frame = 0.0;
uniform bool curv_on; uniform float curvature;
uniform bool vig_on; uniform float vignette;
uniform bool bloom_on; uniform float bloom_threshold; uniform float bloom_radius; uniform float bloom_intensity;
uniform bool chroma_on; uniform float chroma;
uniform bool interlace_on; uniform float interlace;
uniform bool noise_on; uniform float noise;
""" + ShaderBuilder.COMMON + """
vec4 at(vec2 p) {
	if (p.x < 0.0 || p.y < 0.0 || p.x > canvas_px.x || p.y > canvas_px.y) { return vec4(0.0); }
	vec2 s = (p * zoom + pan) / view_size;
	return texture(pre_tex, s);
}
float hash2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
vec4 display_color(vec2 p) {
	vec2 uv = p / canvas_px;
	vec2 c = uv * 2.0 - 1.0;
	if (curv_on) {
		c *= 1.0 + curvature * dot(c, c);
		uv = c * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { return vec4(0.0, 0.0, 0.0, 1.0); }
	}
	vec2 pw = uv * canvas_px;
	vec4 col = at(pw);
	if (chroma_on) {
		vec2 dir = normalize(c + vec2(1e-5)) * chroma * length(c);
		col.r = at(pw + dir).r;
		col.b = at(pw - dir).b;
	}
	if (bloom_on) {
		vec3 acc = vec3(0.0);
		for (int ring = 1; ring <= 2; ring++) {
			for (int k = 0; k < 12; k++) {
				float a = float(k) * TAU / 12.0 + float(ring) * 0.26;
				vec4 s = at(pw + vec2(cos(a), sin(a)) * bloom_radius * float(ring) * 0.5);
				float l = dot(s.rgb, vec3(0.2126, 0.7152, 0.0722));
				acc += s.rgb * s.a * max(l - bloom_threshold, 0.0) / max(1.0 - bloom_threshold, 0.05);
			}
		}
		col.rgb += acc / 24.0 * bloom_intensity * 2.0;
		col.a = max(col.a, clamp(dot(acc, vec3(0.333)) / 24.0 * bloom_intensity * 2.0, 0.0, 1.0));
	}
	if (interlace_on && mod(floor(pw.y) + frame, 2.0) < 1.0) { col.rgb *= 1.0 - interlace; }
	if (noise_on) { col.rgb += (hash2(floor(pw) + vec2(frame * 17.0, frame * 31.0)) - 0.5) * noise; }
	if (vig_on) { col.rgb *= 1.0 - vignette * smoothstep(0.35, 1.45, length(c)); }
	return vec4(clamp(col.rgb, 0.0, 1.0), col.a);
}
void fragment() { COLOR = display_color(canvas_point(UV)); }
"""
	return _shader
