class_name WorldView
extends Node2D
## The town on screen, drawn in code: wet streets under sodium lamps, blocks
## of flats with a few lit windows, the Works, the Bureau, the old quarter,
## the rule wall, rain. Then the people, the cameras and (for citizens) the
## torn pages. What shows depends on who's looking:
##   ruler   - the whole town, but people only where a camera sees
##   citizen - close in round yourself; cameras show where they watch
##   public  - the empty streets, cameras and lamps (the shared screen on the
##             board must never work as one more camera for the ruler)
##   menu    - the whole town, everyone in it (behind the title)
##   eyes    - (watchers) what the cameras see, as the ruler does
##   town    - (watchers) everyone, the citizens labelled (a minute behind)

const COATS := ["4a5260", "51555c", "3f4a57", "5a5650", "48505a", "555a63"]
const HAIR := ["1d1a17", "3b2a1e", "6b5a44", "2a2a2a", "8a8478", "4a3423"]
const RED := Color("c8283a")
const PAPER := Color("e8e1cf")
const LAMP := Color(1.0, 0.68, 0.3)

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

var ground: Node2D
var glow: Node2D
var actors: Node2D
var shade: CanvasModulate
var _walk_phase := {}


func _ready() -> void:
	shade = CanvasModulate.new()
	add_child(shade)
	ground = Ground.new(self)
	add_child(ground)
	glow = Glow.new(self)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	add_child(glow)
	actors = Actors.new(self)
	add_child(actors)


func _process(delta: float) -> void:
	# dusk falls: the town darkens and the lamps take over
	shade.color = Color(0.62, 0.64, 0.72).lerp(Color(0.34, 0.35, 0.48), night)
	actors.queue_redraw()
	glow.queue_redraw()


func world_size() -> Vector2:
	return Vector2(town.w * Town.TILE, town.h * Town.TILE)


## The person under a world point (for the ruler's clicks), or -1.
func person_at(p: Vector2, only_seen := true) -> int:
	var best := -1
	var bd := 18.0
	for i in pos.size():
		if bits[i] & Sim.B_HIDDEN:
			continue
		if only_seen and not seen.has(i):
			continue
		var d := pos[i].distance_to(p)
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


# -------------------------------------------------------------- the ground

class Ground extends Node2D:
	var v: WorldView
	var rng := RandomNumberGenerator.new()

	func _init(view: WorldView) -> void:
		v = view

	func _draw() -> void:
		var t := v.town
		var T := Town.TILE
		rng.seed = 11
		draw_rect(Rect2(Vector2.ZERO, v.world_size()), Color("15171b"))
		for y in t.h:
			for x in t.w:
				var c := t.tile(x, y)
				var r := Rect2(x * T, y * T, T, T)
				var n := rng.randf()
				match c:
					".":
						draw_rect(r, Color("202328").lerp(Color("25292f"), n))
					",":
						draw_rect(r, Color("2b2b30").lerp(Color("303036"), n))
						draw_rect(r, Color(0, 0, 0, 0.25), false, 1.0)
					"o":
						draw_rect(r, Color("231f1c").lerp(Color("29241f"), n))
						for k in 3:
							draw_circle(r.position + Vector2(rng.randf_range(4, 28), rng.randf_range(4, 28)), 3.5, Color("2f2924"))
					"p":
						draw_rect(r, Color("17221a").lerp(Color("1b281e"), n))
					"G":
						draw_rect(r, Color("202328"))
						for k in 5:
							draw_rect(Rect2(r.position + Vector2(3 + k * 6, 2), Vector2(2, 28)), Color("5a5e66"))
					"C":
						draw_rect(r, Color("0c0d0f"))
						for k in 4:
							draw_line(r.position + Vector2(4, 6 + k * 7), r.position + Vector2(28, 6 + k * 7), Color("3a3d42"), 2)
					"T":
						draw_rect(r, Color("17221a") if t.tile(x, y + 1) == "p" or t.tile(x, y - 1) == "p" else Color("2b2b30"))
		# buildings over the ground: each run of solid tiles a slab with a lit edge
		for y in t.h:
			for x in t.w:
				var c := t.tile(x, y)
				if not c in "WHFMBQR":
					continue
				var r := Rect2(x * T, y * T, T, T)
				var col: Color = {"W": Color("0f1013"), "H": Color("2c2f36"), "F": Color("33302b"), "M": Color("2e2a27"),
					"B": Color("2a1214"), "Q": Color("2b2522"), "R": Color("d8d2c0")}[c]
				draw_rect(r, col)
				# roof edges where the slab meets the street
				if not t.tile(x, y - 1) in "WHFMBQR":
					draw_rect(Rect2(r.position, Vector2(T, 4)), col.lightened(0.12))
				if not t.tile(x, y + 1) in "WHFMBQR":
					draw_rect(Rect2(r.position + Vector2(0, T - 6), Vector2(T, 6)), col.darkened(0.45))
				if c == "W" and (x + y) % 2 == 0:
					draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(16, 16)), Color("181a1e"))
				if c in "HQ" and rng.randf() < 0.35:  # windows: a few lit, most dark
					var lit := rng.randf() < 0.4
					draw_rect(Rect2(r.position + Vector2(10, 11), Vector2(8, 9)), Color("e8b65a") if lit else Color("191b20"))
				if c == "F" and x % 3 == 0:
					draw_line(r.position + Vector2(0, 26), r.position + Vector2(16, 6), Color("4a463f"), 3)
		# the Bureau's banner and the wall's posters
		var bureau: Rect2i = t.districts.bureau
		var b := Rect2(Vector2(43 * T, 24 * T), Vector2(13 * T, 7 * T))
		draw_rect(Rect2(b.position + Vector2(b.size.x / 2 - 40, 10), Vector2(80, b.size.y - 20)), RED.darkened(0.25))
		_eye(b.position + Vector2(b.size.x / 2, b.size.y / 2), 26)
		draw_string(v.wall_font, b.position + Vector2(0, b.size.y - 20), "THE BUREAU", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 30, Color(0.85, 0.8, 0.7, 0.55))
		var wall := Rect2(28 * T, 13 * T, 4 * T, T)
		draw_string(v.wall_font, wall.position + Vector2(0, 22), "THE RULES", HORIZONTAL_ALIGNMENT_CENTER, wall.size.x, 22, Color("2a2a2e"))
		# district names, faint, for finding your way
		for k in t.districts:
			var d: Rect2i = t.districts[k]
			var name: String = t.names[k].to_upper().replace("THE ", "")
			draw_string(v.font, Vector2(d.position.x * T + 8, d.position.y * T + 22), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.78, 0.7, 0.32))

	func _eye(c: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		for i in 25:
			var a := PI * i / 12.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.55 * (1 if i <= 12 else 1)))
		draw_colored_polygon(pts, PAPER.darkened(0.2))
		draw_circle(c, r * 0.42, Color("1a0c0d"))
		draw_circle(c, r * 0.16, RED)


# ---------------------------------------------------------------- the light

class Glow extends Node2D:
	var v: WorldView
	var tex: Texture2D

	func _init(view: WorldView) -> void:
		v = view
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
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
		for i in v.town.lamps.size():
			var p: Vector2 = v.town.lamps[i]
			var flick := 1.0 if (i * 37) % 11 != 0 else 0.75 + 0.25 * absf(sin(tm * 9.0 + i))
			var a := (0.10 + 0.22 * v.night) * flick
			draw_texture_rect(tex, Rect2(p - Vector2(78, 78), Vector2(156, 156)), false, Color(lamp, a))
			draw_circle(p, 3.0, Color(lamp, 0.6 + 0.4 * v.night))
		# the cameras' eyes: what the ruler sees is lit
		if v.mode == "ruler" or v.mode == "eyes":
			for c in v.cams:
				if c[3] == 0:
					var mine: bool = int(c[2]) == v.seat
					draw_texture_rect(tex, Rect2(Vector2(c[0], c[1]) - Vector2(Sim.CAM_R, Sim.CAM_R) * 1.25, Vector2(Sim.CAM_R, Sim.CAM_R) * 2.5), false,
						Color(0.75, 0.85, 1.0, 0.32 if mine else 0.2))


# ---------------------------------------------------------------- the people

class Actors extends Node2D:
	var v: WorldView

	func _init(view: WorldView) -> void:
		v = view

	func _draw() -> void:
		var tm := Time.get_ticks_msec() / 1000.0
		# pages (citizens only): scraps of paper, catching the light
		if v.mode == "citizen":
			for g in v.pages:
				var p := Vector2(g[0], g[1])
				draw_set_transform(p, 0.4 + sin(p.x) * 0.5)
				draw_rect(Rect2(-5, -6, 10, 12), WorldView.PAPER)
				draw_line(Vector2(-3, -2), Vector2(3, -2), Color("8a8478"), 1)
				draw_line(Vector2(-3, 1), Vector2(3, 1), Color("8a8478"), 1)
				draw_set_transform(Vector2.ZERO)
				draw_arc(p, 9 + 2 * sin(tm * 3), 0, TAU, 16, Color(1, 1, 1, 0.25), 1.5)
		# cameras: a post with a lens; the circle it watches
		for i in v.cams.size():
			var c: Array = v.cams[i]
			var p := Vector2(c[0], c[1])
			var blind: bool = int(c[3]) == 1
			if v.mode == "ruler" or v.mode == "eyes":
				var mine: bool = int(c[2]) == v.seat or v.mode == "eyes"
				draw_arc(p, Sim.CAM_R, 0, TAU, 48, Color(0.7, 0.85, 1.0, 0.45 if mine else 0.2) if not blind else Color(1, 1, 1, 0.15), 2.0)
				if i == v.picked_cam:
					draw_arc(p, 20, 0, TAU, 24, Color.WHITE, 3)
			elif v.mode == "citizen":
				# you know roughly where they look: a red ring, brighter when it's on you
				var on_me: bool = v.me >= 0 and not blind and p.distance_to(v.pos[v.me]) < Sim.CAM_R
				draw_arc(p, Sim.CAM_R, 0, TAU, 48, Color(WorldView.RED, 0.55 if on_me else 0.22), 2.0 if on_me else 1.5)
			draw_circle(p + Vector2(0, 6), 5, Color(0, 0, 0, 0.4))
			draw_rect(Rect2(p + Vector2(-2, -4), Vector2(4, 12)), Color("3a3d42"))
			draw_circle(p + Vector2(0, -6), 7, Color("1a1c20"))
			draw_circle(p + Vector2(0, -6), 3.5, WorldView.RED if not blind else Color("555"))
		# people
		for i in v.pos.size():
			var b: int = v.bits[i]
			if b & Sim.B_HIDDEN:
				continue
			var p := v.pos[i]
			var visible := v.mode != "public"  # (the shared screen shows empty streets: the board must not be a camera)
			if v.mode == "ruler" or v.mode == "eyes":
				visible = v.seen.has(i)
			if not visible:
				continue
			_person(i, p, b, tm)

	func _person(i: int, p: Vector2, b: int, tm: float) -> void:
		var look: int = v.looks[i]
		var coat := Color(WorldView.COATS[look % WorldView.COATS.size()])
		var hair := Color(WorldView.HAIR[(look * 5 + 1) % WorldView.HAIR.size()])
		var moving := b & Sim.B_MOVING != 0
		var hurry := b & Sim.B_HURRY != 0
		var search := b & Sim.B_SEARCH != 0
		var bob := sin(tm * (16.0 if hurry else 9.0) + i) * (1.5 if moving else 0.0)
		if i == v.me:
			draw_arc(p + Vector2(0, 5), 12, 0, TAU, 24, Color(1, 1, 1, 0.55), 2.0)
		draw_set_transform(p + Vector2(0, 7), 0, Vector2(1, 0.45))
		draw_circle(Vector2.ZERO, 8, Color(0, 0, 0, 0.45))
		draw_set_transform(Vector2.ZERO)
		var h := 0.6 if search else 1.0
		draw_rect(Rect2(p + Vector2(-6, -6 * h + bob * 0.3), Vector2(12, 12 * h)), coat)
		draw_rect(Rect2(p + Vector2(-6, -6 * h + bob * 0.3), Vector2(12, 3)), coat.lightened(0.15))
		draw_circle(p + Vector2(0, -9 * h + bob), 5.0, Color("c9b49a"))
		draw_arc(p + Vector2(0, -10 * h + bob), 5.0, PI, TAU, 10, hair, 3.5)
		if b & Sim.B_NOD:
			var k := fmod(tm * 1.4, 1.0)
			draw_arc(p + Vector2(0, -9), 8 + k * 14, 0, TAU, 20, Color(1, 1, 1, 0.6 * (1 - k)), 1.5)
		if v.mode == "town" and v.cits.has(i):  # (watchers) the citizens, by number
			draw_arc(p + Vector2(0, 5), 11, 0, TAU, 20, Color(WorldView.PAPER, 0.8), 2.0)
			draw_string(v.font, p + Vector2(-30, -20), str(v.cits[i]), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, WorldView.PAPER)
		if (v.mode == "ruler" or v.mode == "eyes") and v.seen.has(i):
			var sus: int = v.seen[i][0]
			var flags: int = v.seen[i][1]
			var bad := flags & ~(Sim.F_SEARCH | Sim.F_NOD) != 0 or flags & (Sim.F_SEARCH | Sim.F_NOD) != 0
			if bad:
				draw_arc(p, 13, 0, TAU, 20, WorldView.RED, 2.5)
			if sus > 0:
				draw_rect(Rect2(p + Vector2(-14, -26), Vector2(28, 4)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(p + Vector2(-14, -26), Vector2(28 * sus / 100.0, 4)), WorldView.RED.lerp(Color("f2c94c"), 1.0 - sus / 100.0))
			if i == v.picked:
				draw_arc(p, 17, 0, TAU, 24, Color.WHITE, 3)
