class_name Figures
extends RefCounted
## The townsfolk, drawn in code. There are twelve kinds of people in the
## town (Sim.LOOKS), and everyone, citizens included, is one of them: a
## citizen is only ever one more works hand or clerk in the crowd, which is
## the whole game. Each kind has a silhouette you can tell at a glance (a
## cap, a brimmed hat, a headscarf, an umbrella...) so the town reads as
## people, while three or four people share every kind.
##
## draw() puts one person at their feet, facing down (towards you), up,
## left or right, mid-step, crouched to search, or nodding.

const INK := Color("121318")
const HEAD := 1.18  # heads (and hats) a little larger than life
enum { DOWN, UP, LEFT, RIGHT }

# coat, trim (collar and cuffs), legs, skin, hair, hair style, hat, hat
# colour, what they carry, its colour, scarf (or ""), half-width, height,
# long coat
const LOOKS := [
	# a works hand: blue overalls, flat cap, a toolbox
	["4d5f78", "6b7f99", "2b3240", "c99a78", "3b2a1e", "short", "cap", "3d434d", "tools", "8a4f32", "", 6.6, 1.0, false],
	# a clerk: long grey coat, brimmed hat, a briefcase
	["5e6168", "7a7e86", "2a2c31", "e3bb98", "2a2420", "short", "brim", "26282d", "case", "5a3a28", "", 5.8, 1.04, true],
	# a shopper: brown coat, a red headscarf, a basket
	["74553e", "8f6c50", "3a2f28", "b07a56", "1d1a17", "short", "scarf", "a2403f", "basket", "b08a52", "", 6.2, 0.96, true],
	# an old man with a stick: dark coat, white hair
	["434651", "5a5e6b", "2c2d33", "e8c4a8", "dedad2", "short", "none", "000000", "cane", "6e5238", "", 6.0, 0.9, true],
	# a student: navy jacket, satchel
	["30416a", "4a5e8c", "2b2b30", "8a5a3c", "1d1a17", "short", "none", "000000", "satchel", "8a6436", "", 5.6, 0.94, false],
	# an olive raincoat under a black umbrella
	["6e6c3e", "898858", "33322a", "d8a882", "6b4a2a", "short", "none", "000000", "umbrella", "1f2128", "", 6.0, 1.0, true],
	# an orderly from the clinic: pale coat, white cap
	["a7b5b0", "c4d0cc", "3c4448", "6e4630", "151312", "bun", "nurse", "eceae2", "none", "000000", "", 5.8, 0.98, true],
	# a porter: green jacket, peaked cap with a brass band
	["2f4d40", "3f6555", "23272a", "c48c64", "2a2018", "short", "peak", "1f2a25", "none", "000000", "", 6.8, 1.02, false],
	# a young one in a mustard wool hat and a teal scarf
	["7d4a37", "99604a", "2c2f38", "f0cfb0", "8a5a2a", "short", "beanie", "c9a54a", "none", "000000", "5f8d8f", 5.6, 0.95, false],
	# a tall man in a long black coat and a wine scarf
	["36383f", "4d5059", "202126", "5a3a28", "161412", "bald", "none", "000000", "none", "000000", "7e2b35", 6.4, 1.1, true],
	# a plum coat, a bob, a red umbrella
	["5c405a", "7a5878", "2f2a33", "e6bc98", "2a1d18", "bob", "none", "000000", "umbrella", "8e3038", "", 5.8, 0.98, true],
	# the baker: apron over a grey coat, a beret, a basket of loaves
	["827c70", "9c968a", "34332f", "a86c48", "2a2018", "short", "beret", "393a48", "apron", "e2ddcf", "", 6.6, 0.98, false],
]

static var _cache: Array = []


static func look(i: int) -> Dictionary:
	if _cache.is_empty():
		for l in LOOKS:
			_cache.append({"coat": Color(l[0]), "trim": Color(l[1]), "legs": Color(l[2]), "skin": Color(l[3]), "hair": Color(l[4]),
				"style": l[5], "hat": l[6], "hatc": Color(l[7]), "carry": l[8], "carryc": Color(l[9]),
				"scarf": Color(l[10]) if l[10] != "" else Color(0, 0, 0, 0), "w": float(l[11]), "h": float(l[12]), "long": l[13]})
	return _cache[posmod(i, _cache.size())]


static func facing_of(d: Vector2, was: int) -> int:
	if d.length_squared() < 0.04:
		return was
	if absf(d.x) > absf(d.y) * 1.1:
		return LEFT if d.x < 0 else RIGHT
	return DOWN if d.y > 0 else UP


## An ellipse as a polygon (rx, ry).
static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, from := 0.0, to := TAU, n := 18) -> void:
	var pts := PackedVector2Array()
	for k in n + 1:
		var a := from + (to - from) * k / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if to - from < TAU - 0.01:
		pts.append(c)
	ci.draw_colored_polygon(pts, col)


## One person, standing at feet. step: their stride's phase (radians).
static func draw(ci: CanvasItem, feet: Vector2, look_i: int, facing: int, step: float, moving: bool, crouch := false, nod := false, size := 1.0) -> void:
	var L := look(look_i)
	var s: float = L.h * size
	var ysc := 0.74 if crouch else 1.0
	ci.draw_set_transform(feet, 0.0, Vector2(s, s * ysc))
	var side := facing == LEFT or facing == RIGHT
	var fx := -1.0 if facing == LEFT else 1.0
	var sw := sin(step) if moving else 0.0
	var w: float = L.w * (0.72 if side else 1.0)
	var hem := -3.0 if L.long else -7.5
	var coat: Color = L.coat
	var hy := -22.5 + (1.3 if nod else 0.0) + (absf(sw) * -0.6 if moving else 0.0)  # the head bobs with the stride
	var legs: Color = L.legs
	var shoe := legs.darkened(0.45)

	# --- outline: a dark edge round the whole figure, so people read on any ground
	var o := 1.1
	if side:
		ci.draw_rect(Rect2(-2.2 - o + sw * 2.4, -9, 4.4 + 2 * o, 9 + o), INK)
		ci.draw_rect(Rect2(-2.2 - o - sw * 2.4, -9, 4.4 + 2 * o, 9 + o), INK)
	else:
		ci.draw_rect(Rect2(-4.6 - o, -9, 9.2 + 2 * o, 9 + o), INK)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-w - o, -17.5 - o), Vector2(w + o, -17.5 - o), Vector2(w + 1.3 + o, hem + o), Vector2(-w - 1.3 - o, hem + o)]), INK)
	ci.draw_circle(Vector2(0, hy), 5.2 * HEAD + o, INK)

	# --- legs, stepping
	if side:
		for k in [-1.0, 1.0]:
			var x: float = sw * 2.4 * k
			var c := legs.darkened(0.25) if k < 0 else legs
			ci.draw_rect(Rect2(x - 1.6, -9, 3.2, 8.2), c)
			ci.draw_rect(Rect2(x - 1.6 + fx * 0.6, -1.6, 3.6, 1.8), shoe)
	else:
		for k in [-1.0, 1.0]:
			var lift := maxf(0.0, sw * k) * 1.8
			ci.draw_rect(Rect2(k * 2.3 - 1.7, -9, 3.4, 8.4 - lift), legs if k < 0 else legs.darkened(0.12))
			ci.draw_rect(Rect2(k * 2.3 - 1.9, -1.8 - lift, 3.8, 1.9), shoe)

	# --- the far arm (side view), behind the body
	if side:
		ci.draw_line(Vector2(-fx * 0.5, -15.5), Vector2(-fx * 0.5 - sw * 3.0, -9.5), coat.darkened(0.3), 2.6)

	# --- the coat: lit from the upper left, a shade down its right side
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-w, -17.5), Vector2(w, -17.5), Vector2(w + 1.3, hem), Vector2(-w - 1.3, hem)]), coat)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.3, -17.5), Vector2(w, -17.5), Vector2(w + 1.3, hem), Vector2(w * 0.4, hem)]), coat.darkened(0.16))
	ci.draw_line(Vector2(-w + 0.6, -16.5), Vector2(-w - 0.5, hem - 0.5), coat.lightened(0.14), 1.0)
	ci.draw_circle(Vector2(-w + 1.6, -16.4), 1.8, coat)
	ci.draw_circle(Vector2(w - 1.6, -16.4), 1.8, coat.darkened(0.16))
	if not side and facing == DOWN:
		# buttons or a zip, and the collar
		if L.long:
			for k in 3:
				ci.draw_circle(Vector2(0.2, -14.0 + k * 3.2), 0.55, coat.darkened(0.45))
		else:
			ci.draw_line(Vector2(0, -16.5), Vector2(0, hem), coat.darkened(0.3), 0.8)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-3.2, -17.8), Vector2(0, -14.8), Vector2(3.2, -17.8)]), L.trim)
	else:
		ci.draw_rect(Rect2(-w + 0.8, -18.2, 2 * w - 1.6, 1.6), L.trim)
	ci.draw_line(Vector2(-w - 1.1, hem - 0.4), Vector2(w + 1.1, hem - 0.4), coat.darkened(0.3), 1.0)

	var carry: String = L.carry
	if carry == "apron":
		if facing == DOWN:
			ci.draw_rect(Rect2(-w * 0.62, -14.5, w * 1.24, 12.5), L.carryc)
			ci.draw_rect(Rect2(-w * 0.62, -14.5, w * 1.24, 1.0), L.carryc.darkened(0.15))
		elif facing == UP:
			ci.draw_line(Vector2(-1.5, -12), Vector2(1.5, -10), L.carryc, 1.0)
			ci.draw_line(Vector2(1.5, -12), Vector2(-1.5, -10), L.carryc, 1.0)
		else:
			ci.draw_rect(Rect2(fx * w * 0.2, -14.5, fx * w * 0.9, 9.5), L.carryc)
	if carry == "satchel":
		ci.draw_line(Vector2(-w + 0.5, -17), Vector2(w - 0.5, -9), L.carryc.darkened(0.2), 1.3)

	# --- arms and hands
	var hand_r := Vector2(w + 0.9, -9.0)
	var hand_l := Vector2(-w - 0.9, -9.0)
	if side:
		hand_r = Vector2(fx * 0.5 + sw * 3.0, -9.5)
		ci.draw_line(Vector2(fx * 0.5, -15.5), hand_r, coat.darkened(0.08), 2.8)
		ci.draw_circle(hand_r, 1.35, L.skin)
		hand_l = hand_r
	else:
		hand_r.y += maxf(0.0, -sw) * 1.4
		hand_l.y += maxf(0.0, sw) * 1.4
		ci.draw_line(Vector2(w - 0.4, -16), hand_r, coat.darkened(0.22), 2.8)
		ci.draw_line(Vector2(-w + 0.4, -16), hand_l, coat.darkened(0.04), 2.8)
		ci.draw_circle(hand_r, 1.35, L.skin.darkened(0.08))
		ci.draw_circle(hand_l, 1.35, L.skin)

	# --- what they carry
	var cc: Color = L.carryc
	match carry:
		"tools":
			var b := Rect2(hand_r + Vector2(-2.8, 0.6), Vector2(5.6, 3.6))
			ci.draw_rect(b.grow(0.8), INK)
			ci.draw_rect(b, cc)
			ci.draw_rect(Rect2(b.position, Vector2(b.size.x, 1.0)), cc.lightened(0.25))
		"case":
			var b := Rect2(hand_r + Vector2(-3.2, 0.8), Vector2(6.4, 4.4))
			ci.draw_rect(b.grow(0.8), INK)
			ci.draw_rect(b, cc)
			ci.draw_line(b.position + Vector2(0, 1.6), b.position + Vector2(b.size.x, 1.6), cc.darkened(0.3), 0.7)
		"basket", "apron":
			if carry == "apron" and facing == UP:
				pass
			else:
				var at := hand_l if carry == "basket" else hand_r
				var b := Rect2(at + Vector2(-3.4, 0.6), Vector2(6.8, 3.8))
				ci.draw_rect(b.grow(0.8), INK)
				ci.draw_rect(b, Color("b08a52") if carry == "apron" else cc)
				ci.draw_arc(at + Vector2(0, 0.8), 3.0, PI, TAU, 8, (Color("b08a52") if carry == "apron" else cc).darkened(0.2), 0.9)
				if carry == "apron":  # loaves
					ci.draw_circle(at + Vector2(-1.6, 0.6), 1.5, Color("c8904a"))
					ci.draw_circle(at + Vector2(1.4, 0.4), 1.5, Color("b47a3c"))
				else:  # greens poking out
					ci.draw_circle(at + Vector2(-1.2, 0.4), 1.2, Color("5f7f46"))
		"cane":
			ci.draw_line(hand_r, Vector2(hand_r.x + (fx * 2.0 if side else 1.4), 0.0), INK, 2.0)
			ci.draw_line(hand_r, Vector2(hand_r.x + (fx * 2.0 if side else 1.4), 0.0), cc, 1.1)
		"satchel":
			var at := Vector2(-w + 0.6, -9.5) if not side else Vector2(-fx * (w - 0.5), -10.0)
			var b := Rect2(at + Vector2(-2.6, -1.8), Vector2(5.2, 4.2))
			ci.draw_rect(b.grow(0.7), INK)
			ci.draw_rect(b, cc)
			ci.draw_rect(Rect2(b.position, Vector2(b.size.x, 1.6)), cc.darkened(0.2))

	# --- scarf
	if L.scarf.a > 0:
		ci.draw_rect(Rect2(-w * 0.75, -19.0, w * 1.5, 2.6), L.scarf)
		if facing == DOWN:
			ci.draw_rect(Rect2(1.0, -17.0, 2.0, 5.0), L.scarf.darkened(0.12))
		elif facing == UP:
			ci.draw_rect(Rect2(-1.0, -17.0, 2.0, 4.0), L.scarf.darkened(0.2))

	# --- the head, drawn a little large (people read by their heads and hats)
	ci.draw_rect(Rect2(-1.5, hy + 3.2, 3.0, 2.4), L.skin.darkened(0.2))  # neck
	ci.draw_set_transform(feet + Vector2(0, hy * s * ysc), 0.0, Vector2(s, s * ysc) * HEAD)
	hy = 0.0
	var H := Vector2(0, hy)
	var skin: Color = L.skin
	var hair: Color = L.hair
	var style: String = L.style
	match facing:
		UP:
			if style == "bald":
				ci.draw_circle(H, 5.0, skin)
				ci.draw_circle(H + Vector2(-1.4, -1.6), 1.6, skin.lightened(0.12))
			else:
				ci.draw_circle(H, 5.0, hair)
				if style == "bob":
					ci.draw_rect(Rect2(-5.6, hy - 0.5, 11.2, 4.6), hair)
				ci.draw_circle(H + Vector2(-1.5, -1.8), 1.8, hair.lightened(0.14))
		DOWN:
			ci.draw_circle(H, 5.0, skin)
			if style != "bald":
				ci.draw_colored_polygon(_cap_pts(H, 5.25, 0.2), hair)  # hair over the top of the head
				if style == "bob":
					ci.draw_rect(Rect2(-5.7, hy - 1.0, 2.1, 5.0), hair)
					ci.draw_rect(Rect2(3.6, hy - 1.0, 2.1, 5.0), hair)
			ci.draw_circle(H + Vector2(-1.8, -1.6), 1.2, skin.lightened(0.15))  # the light on the brow
			ci.draw_circle(H + Vector2(-1.8, 0.7), 0.75, INK)
			ci.draw_circle(H + Vector2(1.8, 0.7), 0.75, INK)
			ci.draw_line(H + Vector2(-0.9, 3.0), H + Vector2(0.9, 3.0), skin.darkened(0.35), 0.7)
		_:
			ci.draw_circle(H, 5.0, skin)
			if style != "bald":
				ci.draw_colored_polygon(_cap_pts(H + Vector2(-fx * 0.8, 0), 5.2, 0.15), hair)
				ci.draw_circle(H + Vector2(-fx * 2.2, 0.6), 3.4, hair)  # the back of the head
				if style == "bob":
					ci.draw_rect(Rect2(-fx * 5.6 - 1.0, hy - 1.0, 2.2 if fx > 0 else -2.2, 5.0), hair)
			ci.draw_circle(H + Vector2(fx * 5.0, 0.8), 1.0, skin)  # nose
			ci.draw_circle(H + Vector2(fx * 2.4, 0.4), 0.75, INK)
	if style == "bun" and L.hat != "nurse":
		ci.draw_circle(H + Vector2(0, -5.2), 2.2, hair)

	# --- hats
	var hc: Color = L.hatc
	match L.hat:
		"cap":  # flat cap, peak to the front
			ci.draw_colored_polygon(_cap_pts(H + Vector2(0, -0.6), 5.5, 0.1), hc)
			if facing == DOWN:
				ellipse(ci, H + Vector2(0, -1.5), 5.2, 1.5, hc.darkened(0.25))
			elif side:
				ci.draw_rect(Rect2(fx * 3.2 - (0.0 if fx > 0 else 3.6), hy - 2.4, 3.6, 1.5), hc.darkened(0.25))
			ci.draw_line(H + Vector2(-3.8, -3.8), H + Vector2(-1.0, -5.2), hc.lightened(0.18), 0.9)
		"brim":  # wide-brimmed hat with a band
			ellipse(ci, H + Vector2(0, -2.6), 8.2, 2.6, INK)
			ellipse(ci, H + Vector2(0, -2.6), 7.4, 2.0, hc)
			ci.draw_rect(Rect2(-4.0, hy - 8.6, 8.0, 6.0), INK)
			ci.draw_rect(Rect2(-3.3, hy - 8.0, 6.6, 5.4), hc)
			ci.draw_rect(Rect2(-3.3, hy - 4.6, 6.6, 1.2), hc.lightened(0.25))
			ci.draw_rect(Rect2(-3.3, hy - 8.0, 2.0, 5.4), hc.lightened(0.1))
		"scarf":  # a headscarf, knotted under the chin
			if facing == UP:
				ci.draw_circle(H, 5.7, hc)
				ci.draw_colored_polygon(PackedVector2Array([H + Vector2(-2.5, 4), H + Vector2(2.5, 4), H + Vector2(0, 8.5)]), hc.darkened(0.15))
			else:
				ci.draw_colored_polygon(_cap_pts(H, 5.9, -0.45), hc)
				if facing == DOWN:
					ci.draw_colored_polygon(PackedVector2Array([H + Vector2(-1.8, 4.6), H + Vector2(1.8, 4.6), H + Vector2(0, 7.0)]), hc.darkened(0.15))
				else:
					ci.draw_circle(H + Vector2(-fx * 2.0, 1.0), 4.0, hc)
			ci.draw_arc(H, 4.6, PI * 1.1, PI * 1.5, 6, hc.lightened(0.2), 1.0)
		"beanie":
			ci.draw_colored_polygon(_cap_pts(H + Vector2(0, -0.8), 5.4, 0.0), hc)
			ci.draw_rect(Rect2(-5.4, hy - 1.6, 10.8, 2.0), hc.darkened(0.2))
			ci.draw_circle(H + Vector2(0, -6.4), 1.8, hc.lightened(0.15))
		"peak":  # a peaked cap with a brass band
			ci.draw_rect(Rect2(-5.0, hy - 7.0, 10.0, 5.2), INK)
			ci.draw_rect(Rect2(-4.4, hy - 6.5, 8.8, 4.4), hc)
			ci.draw_rect(Rect2(-4.4, hy - 3.4, 8.8, 1.1), Color("b89a4a"))
			if facing == DOWN:
				ellipse(ci, H + Vector2(0, -1.6), 4.8, 1.3, INK)
			elif side:
				ci.draw_rect(Rect2(fx * 3.6 - (0.0 if fx > 0 else 3.4), hy - 2.6, 3.4, 1.3), INK)
		"nurse":
			ci.draw_rect(Rect2(-3.6, hy - 7.2, 7.2, 3.0), INK)
			ci.draw_rect(Rect2(-3.1, hy - 6.8, 6.2, 2.3), hc)
			if facing == UP:
				ci.draw_circle(H + Vector2(0, -1.0), 2.4, hair)
		"beret":
			ellipse(ci, H + Vector2(-0.8, -3.6), 5.8, 2.8, INK)
			ellipse(ci, H + Vector2(-0.8, -3.7), 5.2, 2.3, hc)
			ci.draw_circle(H + Vector2(-0.2, -6.2), 0.9, hc)

	# --- an umbrella over it all
	if carry == "umbrella":
		var c := Vector2(fx * 1.0 if side else 0.0, hy - 6.5)
		ci.draw_line(c, Vector2(c.x, hy + 2), INK, 1.0)
		ellipse(ci, c, 12.0, 7.2, INK)
		ellipse(ci, c, 11.0, 6.4, cc)
		ellipse(ci, c + Vector2(0, 0.4), 11.0, 6.0, cc.darkened(0.25), 0.0, PI)
		for k in 6:
			var a := PI + PI * (k + 0.5) / 6.0
			ci.draw_line(c, c + Vector2(cos(a) * 10.4, sin(a) * 6.0), cc.lightened(0.18), 0.8)
		ellipse(ci, c + Vector2(-3.5, -2.6), 3.6, 1.6, Color(1, 1, 1, 0.16))
		ci.draw_circle(c, 1.0, cc.lightened(0.35))
	ci.draw_set_transform(Vector2.ZERO)


## The top part of a circle (hair, a hat): cut straight across at `cut`
## radii below the centre (negative cuts above it).
static func _cap_pts(c: Vector2, r: float, cut: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a0 := asin(clampf(cut, -1, 1))
	for k in 15:
		var a := lerpf(PI - a0, TAU + a0, k / 14.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
