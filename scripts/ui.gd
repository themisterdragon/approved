class_name UI
## The look: a state's posters and forms. Paper on near-black, the Bureau's
## red, square corners, a rubber stamp. Everything is drawn in code.
## Contrast: paper on ink is over 14:1; paper on the red focus fill is over
## 6:1; muted text on ink is over 7:1.

const INK := Color("0e0f12")
const SLATE := Color("1b1d22")
const PAPER := Color("e8e1cf")
const MUTED := Color("b9b3a3")
const RED := Color("a81f30")
const RED_BRIGHT := Color("d83a4c")

static var head: Font = load("res://assets/fonts/Anton-Regular.ttf")
static var body: Font = load("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
static var bold: Font = load("res://assets/fonts/AtkinsonHyperlegible-Bold.ttf")
static var _styles := {}


static func styles() -> Dictionary:
	if _styles.is_empty():
		var n := StyleBoxFlat.new()
		n.bg_color = Color(SLATE, 0.95)
		n.border_color = Color(PAPER, 0.7)
		n.set_border_width_all(2)
		n.set_content_margin_all(12)
		n.shadow_color = Color(0, 0, 0, 0.5)
		n.shadow_size = 6
		n.shadow_offset = Vector2(4, 4)
		var lit := n.duplicate()
		lit.bg_color = RED
		lit.border_color = PAPER
		lit.set_border_width_all(3)
		var dis := n.duplicate()
		dis.bg_color = Color(SLATE, 0.6)
		dis.border_color = Color(PAPER, 0.25)
		_styles = {"normal": n, "lit": lit, "dis": dis}
	return _styles


static func button(text: String, on_press: Callable, parent: Node, size := Vector2(480, 64), font_size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", head)
	b.add_theme_font_size_override("font_size", font_size)
	var st := styles()
	b.add_theme_stylebox_override("normal", st.normal)
	b.add_theme_stylebox_override("hover", st.lit)
	b.add_theme_stylebox_override("focus", st.lit)
	b.add_theme_stylebox_override("pressed", st.lit)
	b.add_theme_stylebox_override("disabled", st.dis)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_disabled_color", Color(PAPER, 0.4))
	for s in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(s, PAPER)
	b.pressed.connect(on_press)
	b.mouse_entered.connect(func():
		if b.focus_mode != Control.FOCUS_NONE and not b.disabled:
			b.grab_focus())
	parent.add_child(b)
	return b


static func label(text: String, font: Font, size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	if parent:
		parent.add_child(l)
	return l


static func panel(parent: Node, alpha := 0.88) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(INK, alpha)
	s.border_color = Color(PAPER, 0.35)
	s.set_border_width_all(1)
	s.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", s)
	parent.add_child(p)
	return p


## A HUD card: dark, a little see-through, a thin paper rule along its top.
static func card(parent: Node, alpha := 0.82) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(INK, alpha)
	s.border_color = Color(PAPER, 0.45)
	s.border_width_top = 2
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 14
	s.content_margin_bottom = 16
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


## A big action button with its key underneath, small: HURRY / Shift.
static func action(title: String, key: String, on_press: Callable, parent: Node, width := 190.0) -> Button:
	var b := button("", on_press, parent, Vector2(width, 78), 26)
	b.focus_mode = Control.FOCUS_NONE
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var t := label(title, head, 28, PAPER, v)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := label(key, bold, 17, Color(PAPER, 0.7), v)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Torn pages as little sheets: the ones you hold, and dashed spaces for the rest.
class Pages extends Control:
	var have := 0
	var need := 3

	func _init() -> void:
		custom_minimum_size = Vector2(3 * 34, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_count(h: int, n: int) -> void:
		if h != have or n != need:
			have = h
			need = n
			custom_minimum_size.x = n * 34
			queue_redraw()

	func _draw() -> void:
		for i in need:
			var r := Rect2(Vector2(i * 34 + 2, 3), Vector2(26, 34))
			if i < have:
				draw_set_transform(r.get_center(), -0.08 + 0.08 * i)
				var c := Rect2(-r.size / 2, r.size)
				draw_rect(c.grow(1.5), UI.INK)
				draw_rect(c, UI.PAPER)
				draw_colored_polygon(PackedVector2Array([c.position + Vector2(c.size.x - 8, 0), c.position + Vector2(c.size.x, 0), c.position + Vector2(c.size.x, 8)]), UI.MUTED)
				for k in 4:
					draw_line(c.position + Vector2(5, 10 + k * 5), c.position + Vector2(c.size.x - 5 - (k % 2) * 5, 10 + k * 5), Color("8a8478"), 1.5)
				draw_set_transform(Vector2.ZERO)
			else:
				for k in 8:  # a dashed outline
					var a := k / 8.0
					var b2 := (k + 0.5) / 8.0
					var per := func(t: float) -> Vector2:
						var d := t * 2 * (r.size.x + r.size.y)
						if d < r.size.x: return r.position + Vector2(d, 0)
						d -= r.size.x
						if d < r.size.y: return r.position + Vector2(r.size.x, d)
						d -= r.size.y
						if d < r.size.x: return r.position + Vector2(r.size.x - d, r.size.y)
						d -= r.size.x
						return r.position + Vector2(0, r.size.y - d)
					draw_line(per.call(a), per.call(b2), Color(UI.PAPER, 0.45), 2)


## A rubber stamp: a word in a red box, a little crooked, ink a little worn.
class Stamp extends Control:
	var text := "APPROVED"
	var size_px := 96
	var tilt := -0.12
	var color := UI.RED_BRIGHT

	func _init(t := "APPROVED", px := 96, angle := -0.12) -> void:
		text = t
		size_px = px
		tilt = angle
		var w := UI.head.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		custom_minimum_size = Vector2(w + px * 0.9, px * 1.6)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2
		draw_set_transform(c, tilt)
		var w := UI.head.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var box := Rect2(Vector2(-w / 2 - size_px * 0.3, -size_px * 0.62), Vector2(w + size_px * 0.6, size_px * 1.24))
		draw_rect(box, color, false, maxf(4.0, size_px * 0.07))
		draw_rect(box.grow(-size_px * 0.1), Color(color, 0.6), false, 2.0)
		draw_string(UI.head, Vector2(-w / 2, size_px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
		# worn ink: a few gaps where the stamp didn't take
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(text)
		for i in 14:
			var p := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
			draw_circle(p, rng.randf_range(1.5, 4.0), UI.INK)
		draw_set_transform(Vector2.ZERO)


## Film grain and a heavy vignette over everything: the screen feels like
## something you're not supposed to be looking at.
static func grain() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.035;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.85);
	float v = smoothstep(0.45, 1.0, length(d) * 1.3) * 0.45;  // the vignette's darkness
	float n = h(floor(FRAGCOORD.xy / 2.0) + floor(TIME * 18.0));
	float g = strength;  // the grain's
	float a = g + v - g * v;
	COLOR = vec4((vec3(n) * g + vec3(0.01, 0.01, 0.02) * v) / max(a, 0.001), a);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	return r


## Rain, slanting across the screen.
static func rain() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var img := Image.create(2, 22, false, Image.FORMAT_RGBA8)
	for y in 22:
		for x in 2:
			img.set_pixel(x, y, Color(0.75, 0.8, 0.9, 0.35 * y / 22.0))
	p.texture = ImageTexture.create_from_image(img)
	p.amount = 140
	p.lifetime = 1.1
	p.preprocess = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1300, 10)
	p.position = Vector2(1100, -40)
	p.direction = Vector2(-0.25, 1)
	p.spread = 2
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 1000
	p.initial_velocity_max = 1300
	p.particle_flag_align_y = true
	p.local_coords = false
	return p
