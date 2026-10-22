class_name WorldView
extends Node2D
## The town on screen. The town itself (scripts/town_art.gd) is painted once
## into a picture; over it, live: the people (scripts/figures.gd), the
## cameras, the torn pages, chimney smoke, rain splashes, and the light
## (sodium lamps pooling on the wet street, windows after dark, the
## Bureau's eye). What shows depends on who's looking:
##   ruler   - the whole town, but people only where a camera sees
##   citizen - close in round yourself; cameras show where they watch
##   public  - the empty streets, cameras and lamps (the shared screen on the
##             board must never work as one more camera for the ruler)
##   menu    - the whole town, everyone in it (behind the title)
##   eyes    - (watchers) what the cameras see, as the ruler does
##   town    - (watchers) everyone, the citizens labelled (a minute behind)

const RED := Color("c8283a")
const PAPER := Color("e8e1cf")
const LAMP := Color(1.0, 0.7, 0.34)
const BAKE := 2.0  # the town is painted at twice its size, so it stays sharp up close

static var _baked: Texture2D
static var _art := {}  # windows, chimneys, eye: from the painting

var town := Town.get_town()
var mode := "public"
var me := -1             # (citizen) which person is you
var pos := PackedVector2Array()
var looks := PackedInt32Array()
var bits := PackedInt32Array()
var cams: Array = []     # [x, y, owner, blind]
var seen := {}           # (ruler) person -> [sus, flags]
var pages: Array = []    # (citizen) [x, y]
var seat := 0            # (ruler) whose cameras are yours (-1: watching, none are)
var cits := {}           # (watchers of the whole town) person -> citizen number
var night := 0.0         # 0 day .. 1 night (eases)
var picked := -1         # (ruler) the person picked to be taken
var picked_cam := -1     # (ruler) the camera being moved
var hover_cell := Vector2i(-1, -1)
var font: Font = load("res://assets/fonts/AtkinsonHyperlegible-Bold.ttf")
var wall_font: Font = load("res://assets/fonts/Anton-Regular.ttf")

var ground: Sprite2D
var glow: Node2D
var actors: Node2D
var shade: CanvasModulate
# each person's last place, which way they face, and their stride
var _last := {}
var _face := {}
var _step := {}


func _ready() -> void:
	shade = CanvasModulate.new()
	add_child(shade)
	ground = Sprite2D.new()
	ground.centered = false
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(ground)
	actors = Actors.new(self)
	add_child(actors)
	glow = Glow.new(self)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	add_child(glow)
	_bake()


## Paint the town once (the first screen to need it), then keep the picture.
func _bake() -> void:
	if _baked == null:
		var vp := SubViewport.new()
		vp.size = Vector2i(world_size() * BAKE)
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var art := TownArt.new()
		art.scale = Vector2(BAKE, BAKE)
		vp.add_child(art)
		add_child(vp)
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.generate_mipmaps()
		_baked = ImageTexture.create_from_image(img)
		_art = {"windows": art.windows.duplicate(), "chimneys": art.chimneys.duplicate(), "eye": art.eye}
		vp.queue_free()
	ground.texture = _baked
	ground.scale = Vector2.ONE / BAKE


func _process(_delta: float) -> void:
	# dusk falls: the town cools and darkens and the lamps take over
	shade.color = Color(0.95, 0.95, 1.0).lerp(Color(0.5, 0.54, 0.76), night)
	_track()
	actors.queue_redraw()
	glow.queue_redraw()


## Which way everyone faces, and how far into their stride they are.
func _track() -> void:
	for i in pos.size():
		var p := pos[i]
		var was: Vector2 = _last.get(i, p)
		var d := p - was
		if d.length() > 40:  # (taken away, let go, or a new snapshot order)
			d = Vector2.ZERO
		_face[i] = Figures.facing_of(d, _face.get(i, Figures.DOWN))
		_step[i] = fmod(float(_step.get(i, float(i))) + d.length() * 0.42, TAU)
		_last[i] = p


func world_size() -> Vector2:
	return Vector2(town.w * Town.TILE, town.h * Town.TILE)


## The person under a world point (for the ruler's clicks), or -1.
func person_at(p: Vector2, only_seen := true) -> int:
	var best := -1
	var bd := 22.0
	for i in pos.size():
		if bits[i] & Sim.B_HIDDEN:
			continue
		if only_seen and not seen.has(i):
			continue
		var d := (pos[i] + Vector2(0, -8)).distance_to(p)  # (the middle of them, not their feet)
		if d < bd:
			bd = d
			best = i
	return best


func cam_at(p: Vector2) -> int:
	for i in cams.size():
		if Vector2(cams[i][0], cams[i][1]).distance_to(p) < 22:
			return i
	return -1


func cam_sees(p: Vector2) -> bool:
	for c in cams:
		if c[3] == 0 and Vector2(c[0], c[1]).distance_squared_to(p) < Sim.CAM_R * Sim.CAM_R:
			return true
	return false


func shows_cameras() -> bool:
	return mode == "ruler" or mode == "eyes"


# ---------------------------------------------------------------- the light

class Glow extends Node2D:
	var v: WorldView
	var tex: Texture2D

	func _init(view: WorldView) -> void:
		v = view
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.45))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		tex = gt

	func _draw() -> void:
		var tm := Time.get_ticks_msec() / 1000.0
		var lamp := WorldView.LAMP
		var n := v.night
		for i in v.town.lamps.size():
			var head: Vector2 = v.town.lamps[i] + Vector2(2, -21)
			var flick := 1.0 if (i * 37) % 11 != 0 else 0.75 + 0.25 * absf(sin(tm * 9.0 + i))
			var a := (0.06 + 0.3 * n) * flick
			# the pool of light on the ground, a streak reflected in the wet, the bulb
			draw_texture_rect(tex, Rect2(head + Vector2(-80, -46), Vector2(160, 120)), false, Color(lamp, a))
			draw_texture_rect(tex, Rect2(head + Vector2(-7, 14), Vector2(14, 46)), false, Color(lamp, a * 0.9))
			draw_texture_rect(tex, Rect2(head - Vector2(12, 12), Vector2(24, 24)), false, Color(lamp, 0.25 + 0.5 * n))
		if n > 0.05:
			for w in _art_list("windows"):
				var r: Rect2 = w
				draw_rect(r, Color(WorldView.LAMP, 0.35 * n))
				draw_texture_rect(tex, r.grow(10), false, Color(WorldView.LAMP, 0.14 * n))
		var eye: Vector2 = WorldView._art.get("eye", Vector2.ZERO)
		if eye != Vector2.ZERO:
			var pulse := 0.5 + 0.5 * sin(tm * 1.3)
			draw_texture_rect(tex, Rect2(eye - Vector2(60, 40), Vector2(120, 80)), false, Color(1, 0.15, 0.2, (0.08 + 0.12 * n) * (0.7 + 0.3 * pulse)))
		# the cameras' eyes: what the ruler sees is lit
		if v.shows_cameras():
			for c in v.cams:
				if c[3] == 0:
					var mine: bool = int(c[2]) == v.seat or v.mode == "eyes"
					var R := Sim.CAM_R
					draw_texture_rect(tex, Rect2(Vector2(c[0], c[1]) - Vector2(R, R) * 1.2, Vector2(R, R) * 2.4), false,
						Color(0.7, 0.85, 1.0, 0.26 if mine else 0.14))

	func _art_list(k: String) -> Array:
		return WorldView._art.get(k, [])


# ---------------------------------------------------------------- the people

class Actors extends Node2D:
	var v: WorldView
	var rng := RandomNumberGenerator.new()
	var fig := 1.0

	func _init(view: WorldView) -> void:
		v = view

	func _draw() -> void:
		var tm := Time.get_ticks_msec() / 1000.0
		_splashes(tm)
		# pages (citizens only): scraps of paper, catching the light
		if v.mode == "citizen":
			for g in v.pages:
				var p := Vector2(g[0], g[1])
				var bob := sin(tm * 2.5 + p.x) * 1.5
				Figures.ellipse(self, p + Vector2(0, 4), 7, 2.5, Color(0, 0, 0, 0.35))
				draw_set_transform(p + Vector2(0, -3 + bob), 0.3 + sin(p.x) * 0.4)
				draw_rect(Rect2(-7, -9, 14, 18), Color("8a8070"))
				draw_rect(Rect2(-6, -8, 12, 16), WorldView.PAPER)
				draw_colored_polygon(PackedVector2Array([Vector2(2, -8), Vector2(6, -8), Vector2(6, -3)]), Color("b9b09a"))
				for k in 4:
					draw_line(Vector2(-4, -4 + k * 3.2), Vector2(3 - (k % 2) * 3, -4 + k * 3.2), Color("8a8478"), 1)
				draw_set_transform(Vector2.ZERO)
				var k2 := fmod(tm * 0.8 + p.x * 0.01, 1.0)
				draw_arc(p + Vector2(0, -3), 12 + k2 * 10, 0, TAU, 24, Color(1, 0.95, 0.8, 0.5 * (1 - k2)), 2.0)
		# cameras: the circle they watch, then the camera on its pole
		for i in v.cams.size():
			var c: Array = v.cams[i]
			var p := Vector2(c[0], c[1])
			var blind: bool = int(c[3]) == 1
			if v.shows_cameras():
				var mine: bool = int(c[2]) == v.seat or v.mode == "eyes"
				draw_arc(p, Sim.CAM_R, 0, TAU, 64, Color(0.7, 0.85, 1.0, 0.55 if mine else 0.25) if not blind else Color(1, 1, 1, 0.15), 2.5)
				if i == v.picked_cam:
					draw_arc(p, 24, 0, TAU, 32, Color.WHITE, 3)
			elif v.mode == "citizen":
				# you know roughly where they look: a red ring, brighter when it's on you
				var on_me: bool = v.me >= 0 and v.me < v.pos.size() and not blind and p.distance_to(v.pos[v.me]) < Sim.CAM_R
				if on_me:
					draw_circle(p, Sim.CAM_R, Color(WorldView.RED, 0.07))
				draw_arc(p, Sim.CAM_R, 0, TAU, 64, Color(WorldView.RED, 0.7 if on_me else 0.3), 3.0 if on_me else 2.0)
			_camera(p, blind, tm, i)
		# people, back to front
		var order := []
		for i in v.pos.size():
			if v.bits[i] & Sim.B_HIDDEN:
				continue
			var visible := v.mode != "public"  # (the shared screen shows empty streets: the board must not be a camera)
			if v.shows_cameras():
				visible = v.seen.has(i)
			if visible:
				order.append(i)
		order.sort_custom(func(a, b): return v.pos[a].y < v.pos[b].y)
		var hover := -1
		if v.mode == "ruler":
			hover = v.person_at(get_global_mouse_position())
		# seen from far off (the whole town), people are drawn a little larger
		fig = clampf(1.3 / get_canvas_transform().get_scale().x, 1.0, 1.45)
		for i in order:
			_person(i, v.pos[i], v.bits[i], tm, i == hover)
		_smoke(tm)

	func _camera(p: Vector2, blind: bool, tm: float, i: int) -> void:
		Figures.ellipse(self, p + Vector2(4, 4), 7, 3, Color(0, 0, 0, 0.4))
		draw_rect(Rect2(p + Vector2(-2, -22), Vector2(4, 26)), Color("2a2d33"))
		draw_rect(Rect2(p + Vector2(-1, -22), Vector2(1.5, 26)), Color("454952"))
		# the housing, angled down at the street, and its lens
		draw_set_transform(p + Vector2(0, -24), -0.35 + 0.25 * sin(tm * 0.6 + i))
		draw_rect(Rect2(-9, -5, 18, 10), Color("101114"))
		draw_rect(Rect2(-8, -4, 16, 8), Color("d6d2c6"))
		draw_rect(Rect2(-8, 1, 16, 3), Color("a9a59a"))
		draw_rect(Rect2(8, -3.5, 3, 7), Color("101114"))
		draw_circle(Vector2(10, 0), 2.6, WorldView.RED if not blind else Color("555"))
		draw_set_transform(Vector2.ZERO)
		if not blind and fmod(tm + i * 0.37, 1.6) < 0.25:
			draw_circle(p + Vector2(-5, -27), 1.6, Color(1, 0.3, 0.3))

	func _person(i: int, p: Vector2, b: int, tm: float, hover: bool) -> void:
		var search := b & Sim.B_SEARCH != 0
		var moving := b & Sim.B_MOVING != 0
		var nod := b & Sim.B_NOD != 0
		var feet := p + Vector2(0, 7)
		var watcher := v.shows_cameras() and v.seen.has(i)
		# the ground under them: shadow, and your own ring
		Figures.ellipse(self, feet, 9, 3.6, Color(0, 0, 0, 0.42))
		if i == v.me:
			_ring(feet, 13, 5.2, Color(WorldView.PAPER, 0.9), 2.0)
		if watcher:
			var flags: int = v.seen[i][1]
			if flags != 0:
				_ring(feet, 14, 5.6, WorldView.RED, 3.0)
			if i == v.picked:
				_ring(feet, 17, 7, Color.WHITE, 3.0)
			elif hover:
				_ring(feet, 15, 6, Color(1, 1, 1, 0.6), 1.5)
		if v.mode == "town" and v.cits.has(i):
			_ring(feet, 14, 5.6, Color(WorldView.PAPER, 0.85), 2.0)
		Figures.draw(self, feet, v.looks[i], v._face.get(i, Figures.DOWN), v._step.get(i, 0.0), moving, search, nod, fig)
		var top := p + Vector2(0, -30 * fig + 7 * (fig - 1))
		if nod:
			var k := fmod(tm * 1.4, 1.0)
			draw_arc(p + Vector2(0, -16), 10 + k * 16, 0, TAU, 24, Color(1, 1, 1, 0.7 * (1 - k)), 2.0)
		if i == v.me:  # a marker over your head, so you never lose yourself in the crowd
			var y := top.y - 6 + sin(tm * 3.0) * 1.5
			var tri := PackedVector2Array([Vector2(p.x - 6, y - 7), Vector2(p.x + 6, y - 7), Vector2(p.x, y)])
			draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(-2, -1.5), tri[1] + Vector2(2, -1.5), tri[2] + Vector2(0, 2.5)]), Figures.INK)
			draw_colored_polygon(tri, WorldView.PAPER)
		if v.mode == "town" and v.cits.has(i):  # (watchers) the citizens, by number
			_tag(top + Vector2(0, -4), str(v.cits[i]), WorldView.PAPER, Figures.INK)
		if watcher:
			var sus: int = v.seen[i][0]
			if sus > 0:
				var bar := Rect2(top + Vector2(-16, -8), Vector2(32, 5))
				draw_rect(bar.grow(1), Color(0, 0, 0, 0.7))
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * sus / 100.0, bar.size.y)), WorldView.RED.lerp(Color("f2c94c"), 1.0 - sus / 100.0))

	func _ring(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
		var pts := PackedVector2Array()
		for k in 33:
			var a := TAU * k / 32.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, col, width, true)

	func _tag(at: Vector2, text: String, fg: Color, bg: Color) -> void:
		var w := v.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10
		draw_rect(Rect2(at + Vector2(-w / 2, -16), Vector2(w, 18)), Color(bg, 0.85))
		draw_string(v.font, at + Vector2(-w / 2 + 5, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, fg)

	## Smoke from the chimneys, drifting off east with the weather.
	func _smoke(tm: float) -> void:
		var ch: Array = WorldView._art.get("chimneys", [])
		for j in ch.size():
			var p: Vector2 = ch[j] + Vector2(0, -13)
			for k in 5:
				var a := fmod(tm * 0.35 + k / 5.0 + j * 0.13, 1.0)
				var c := p + Vector2(a * 34 + sin(tm + k) * 2, -a * 30)
				draw_circle(c, 3 + a * 9, Color(0.62, 0.62, 0.66, 0.32 * (1 - a)))

	## Rain landing: little rings on the street round about.
	func _splashes(tm: float) -> void:
		var view := get_viewport_rect()
		var inv := get_canvas_transform().affine_inverse()
		var a := inv * view.position
		var b := inv * view.end
		var area := Rect2(a, b - a)
		rng.seed = 5
		for k in 40:
			var phase := fmod(tm * 1.7 + rng.randf(), 1.0)
			var cyc := floorf(tm * 1.7 + rng.randf())
			var sx := rng.randf()
			var sy := rng.randf()
			var p := area.position + Vector2(fposmod(sx + cyc * 0.618, 1.0) * area.size.x, fposmod(sy + cyc * 0.382, 1.0) * area.size.y)
			if v.town.solid_at(p):
				continue
			_ring(p, 2 + phase * 6, (2 + phase * 6) * 0.4, Color(0.75, 0.82, 0.95, 0.35 * (1 - phase)), 1.0)
