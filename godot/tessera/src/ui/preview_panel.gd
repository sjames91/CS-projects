class_name PreviewPanel
extends VBoxContainer
## Always shows the whole image, fully rendered (never UI), fit to the panel.
## Optional Palette Lock view shows exactly what the exported PNG will be.
## Click/drag moves the main canvas there.

signal navigate(canvas_point: Vector2)

var hub: RenderHub
var view: CompositeView
var container: SubViewportContainer
var _area: Control
var _lock_mat: ShaderMaterial
var _lock_toggle: CheckBox
var canvas_view: CanvasView


func setup(h: RenderHub, cv: CanvasView) -> void:
	hub = h
	canvas_view = cv
	name = "Preview"
	var bar := HBoxContainer.new()
	bar.add_child(UiKit.label("Preview"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_lock_toggle = UiKit.toggle("Palette Lock view", App.preview_lock, func(on): App.set_view("preview_lock", on),
		"Show the image snapped to the palette, as the export will be")
	bar.add_child(_lock_toggle)
	add_child(bar)
	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.custom_minimum_size = Vector2(120, 120)
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_area.gui_input.connect(_on_input)
	_area.draw.connect(_draw_bg)
	_area.resized.connect(_layout)
	add_child(_area)
	container = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(container)
	view = CompositeView.new()
	container.add_child(view)
	view.setup(hub, false)
	_lock_mat = ShaderMaterial.new()
	_lock_mat.shader = _lock_shader()
	App.view_changed.connect(_on_view)
	App.palette_changed.connect(_on_view)
	App.document_changed.connect(_layout)
	cv.view_moved.connect(_area.queue_redraw)
	_on_view()


func _on_view() -> void:
	_lock_toggle.set_pressed_no_signal(App.preview_lock)
	container.material = _lock_mat if App.preview_lock else null
	_lock_mat.set_shader_parameter("palette_tex", hub.palette_tex)
	_lock_mat.set_shader_parameter("pal_count", App.project.palette.size())
	var lock := App.project.palette_lock
	_lock_mat.set_shader_parameter("dither_on", bool(lock.get("dither", false)))
	_lock_mat.set_shader_parameter("dither_strength", float(lock.get("strength", 0.5)))
	_layout()


## Fit the whole canvas into the panel.
func _layout() -> void:
	if view == null:
		return
	var px := App.project.canvas_px()
	var avail := _area.size
	if avail.x < 4 or avail.y < 4:
		return
	var s := minf(avail.x / px.x, avail.y / px.y)
	var img := (px * s).floor().max(Vector2.ONE)
	container.position = ((avail - img) * 0.5).floor()
	container.size = img
	view.set_view(s, Vector2.ZERO)
	_lock_mat.set_shader_parameter("canvas_px", px)
	_area.queue_redraw()


func _draw_bg() -> void:
	_area.draw_rect(Rect2(Vector2.ZERO, _area.size), Color(0.08, 0.08, 0.1))
	var r := Rect2(container.position, container.size)
	var step := 8.0
	_area.draw_rect(r, Color(0.32, 0.32, 0.35))
	var y := 0.0
	while y < r.size.y:
		var x := fmod(y / step, 2.0) * step
		while x < r.size.x:
			_area.draw_rect(Rect2(r.position + Vector2(x, y), Vector2(step, step)).intersection(r), Color(0.4, 0.4, 0.43))
			x += step * 2.0
		y += step


func _on_input(e: InputEvent) -> void:
	var press: bool = e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	var drag: bool = e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if press or drag:
		var px := App.project.canvas_px()
		var local: Vector2 = (e.position - container.position) / container.size * px
		navigate.emit(local.clamp(Vector2.ZERO, px))


func _lock_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform sampler2D palette_tex : filter_nearest;
uniform int pal_count = 0;
uniform bool dither_on = false;
uniform float dither_strength = 0.5;
uniform vec2 canvas_px = vec2(512.0);
#define PAL_RGB(i) texelFetch(palette_tex, ivec2(i, 0), 0).rgb
#define PAL_LAB(i) rgb_to_oklab(PAL_RGB(i))
""" + OkLab.GLSL + OkLab.BAYER_GLSL + OkLab.SNAP_GLSL + """
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (pal_count > 0 && c.a > 0.0) {
		ivec2 px = ivec2(floor(UV * canvas_px));
		c.rgb = snap_pick(rgb_to_oklab(c.rgb), px, pal_count, dither_on, dither_strength);
	}
	COLOR = c;
}
"""
	return s
