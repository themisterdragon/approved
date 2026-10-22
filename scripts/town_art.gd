class_name TownArt
extends Node2D
## The town itself, painted once in code and kept as a picture: seen from
## above and a little to the south, so every building shows its roof and its
## front (windows, doors, shutters), with pavements along the kerbs, wet
## asphalt with puddles, the square's flagstones, the old quarter's cobbles,
## the gardens, trees, lamp posts and the wall round it all.
##
## Each building fills exactly its solid tiles (the front is the bottom row
## of tiles), so what you see is where you can't walk.
## windows / chimneys / eyes: what the light and smoke layers need.

const T := Town.TILE

const ROOF := {"H": "5d636e", "#": "5d636e", "F": "50535a", "M": "6e6656", "B": "2d2427", "Q": "8a4c38", "W": "6c6a70", "R": "4a3c34"}
const FRONT := {"H": "7c828e", "#": "7c828e", "F": "7d4a3c", "M": "8e7f62", "B": "4a1c22", "Q": "a8977a", "W": "5c5a60", "R": "3d322c"}
const STREET := Color("3d424c")
const KERB := Color("575c67")
const PAVING := Color("5c5f67")
const COBBLE := Color("4c4239")
const GRASS := Color("38573b")
const LIT := Color("f2c46e")
const DARK_GLASS := Color("262b36")

var town := Town.get_town()
var windows: Array[Rect2] = []   # lit windows (they glow after dark)
var chimneys: Array[Vector2] = []
var eye := Vector2.ZERO          # the Bureau's eye
var font: Font = load("res://assets/fonts/AtkinsonHyperlegible-Bold.ttf")
var wall_font: Font = load("res://assets/fonts/Anton-Regular.ttf")
var rng := RandomNumberGenerator.new()


func _solid(x: int, y: int) -> bool:
	return town.tile(x, y) in "WHFMBQR#"


func _building(x: int, y: int) -> String:
	var c := town.tile(x, y)
	return c if c in "WHFMBQR#" else ""


func _draw() -> void:
	rng.seed = 11
	windows.clear()
	chimneys.clear()
	draw_rect(Rect2(0, 0, town.w * T, town.h * T), STREET)
	for y in town.h:
		for x in town.w:
			_ground(x, y)
	# shadows fall to the south east, onto the ground beside each building
	for y in town.h:
		for x in town.w:
			if _solid(x, y):
				continue
			var r := Rect2(x * T, y * T, T, T)
			if _solid(x - 1, y):
				draw_rect(Rect2(r.position, Vector2(9, T)), Color(0, 0, 0, 0.22))
				draw_rect(Rect2(r.position, Vector2(4, T)), Color(0, 0, 0, 0.12))
			if _solid(x, y - 1):
				draw_rect(Rect2(r.position, Vector2(T, 5)), Color(0, 0, 0, 0.28))
	for y in town.h:
		for x in town.w:
			if _solid(x, y):
				_block(x, y)
	_rule_wall()
	_bureau()
	for y in town.h:
		for x in town.w:
			if town.tile(x, y) == "T":
				_tree(Vector2(x * T + T / 2.0, y * T + T / 2.0))
	for p in chimneys:  # brick stacks (the smoke is drawn live)
		draw_rect(Rect2(p + Vector2(-5, -12), Vector2(10, 16)), Color("1d1a18"))
		draw_rect(Rect2(p + Vector2(-4, -11), Vector2(8, 15)), Color("6e3e32"))
		draw_rect(Rect2(p + Vector2(-4, -11), Vector2(3, 15)), Color("82503f"))
		draw_rect(Rect2(p + Vector2(-5, -13), Vector2(10, 3)), Color("3a3634"))
	for p in town.lamps:
		_lamp_post(p)
	_exits()
	_names()


# ---------------------------------------------------------------- ground

func _ground(x: int, y: int) -> void:
	var c := town.tile(x, y)
	var r := Rect2(x * T, y * T, T, T)
	var n := rng.randf()
	if c == "T":  # under a tree: whatever is round it
		c = "p" if town.tile(x, y + 1) == "p" or town.tile(x, y - 1) == "p" or town.tile(x - 1, y) == "p" else ","
	match c:
		".", "G":
			draw_rect(r, STREET.lerp(Color("444955"), n * 0.6))
			for k in 3:  # grit
				draw_rect(Rect2(r.position + Vector2(rng.randf_range(2, 28), rng.randf_range(2, 28)), Vector2(2, 2)), Color(1, 1, 1, 0.035))
			# pavement where the street meets a building
			if _solid(x, y - 1) and town.tile(x, y - 1) != "W":
				draw_rect(Rect2(r.position, Vector2(T, 10)), KERB)
				draw_rect(Rect2(r.position + Vector2(0, 10), Vector2(T, 2)), KERB.darkened(0.35))
				draw_line(r.position + Vector2(16, 0), r.position + Vector2(16, 10), KERB.darkened(0.15), 1)
			if _solid(x, y + 1) and town.tile(x, y + 1) != "W":
				draw_rect(Rect2(r.position + Vector2(0, T - 8), Vector2(T, 8)), KERB)
				draw_rect(Rect2(r.position + Vector2(0, T - 9), Vector2(T, 1.5)), KERB.lightened(0.15))
			if _solid(x - 1, y) and town.tile(x - 1, y) != "W":
				draw_rect(Rect2(r.position, Vector2(8, T)), KERB.darkened(0.06))
			if _solid(x + 1, y) and town.tile(x + 1, y) != "W":
				draw_rect(Rect2(r.position + Vector2(T - 8, 0), Vector2(8, T)), KERB.darkened(0.06))
			# a puddle now and then, catching the sky
			if rng.randf() < 0.05:
				var at := r.position + Vector2(rng.randf_range(10, 22), rng.randf_range(12, 22))
				var rx := rng.randf_range(7, 13)
				Figures.ellipse(self, at, rx, rx * 0.42, Color(0.17, 0.19, 0.24, 0.55), 0.0, TAU, 20)
				Figures.ellipse(self, at + Vector2(rx * 0.1, 0.5), rx * 0.75, rx * 0.28, Color(0.15, 0.17, 0.22, 0.6), 0.0, TAU, 20)
				draw_line(at + Vector2(-rx * 0.5, -rx * 0.18), at + Vector2(rx * 0.1, -rx * 0.24), Color(0.62, 0.68, 0.8, 0.22), 1.5)
			# the avenues' centre lines
			if (x == 21 or x == 38) and y % 2 == 0 and not _solid(x, y):
				draw_rect(Rect2(r.position + Vector2(15, 4), Vector2(2, 14)), Color(0.85, 0.82, 0.7, 0.18))
			if (y == 12 or y == 22) and x % 2 == 0 and (x < 21 or x > 38):
				draw_rect(Rect2(r.position + Vector2(4, 15), Vector2(14, 2)), Color(0.85, 0.82, 0.7, 0.18))
		",":
			draw_rect(r, PAVING.lerp(Color("62656d"), n))
			for k in 2:
				for j in 2:
					var slab := Rect2(r.position + Vector2(k * 16, j * 16), Vector2(16, 16))
					draw_rect(slab.grow(-1), PAVING.lerp(Color("666971"), rng.randf()))
					draw_line(slab.position + Vector2(1, 1), slab.position + Vector2(15, 1), Color(1, 1, 1, 0.06), 1)
			if rng.randf() < 0.02:
				var at := r.position + Vector2(16, 18)
				Figures.ellipse(self, at, 11, 4.5, Color(0.2, 0.22, 0.27, 0.45), 0.0, TAU, 20)
				draw_line(at + Vector2(-5, -1.5), at + Vector2(1, -2), Color(0.62, 0.68, 0.8, 0.2), 1.5)
		"o", "C":
			draw_rect(r, COBBLE.darkened(0.2))
			for j in 4:
				for k in 4:
					var off := 4.0 if j % 2 == 1 else 0.0
					var at := r.position + Vector2(k * 8 + 4 + off + rng.randf_range(-0.8, 0.8), j * 8 + 4)
					if at.x > r.position.x + T:
						continue
					var col := COBBLE.lerp(Color("5e5246"), rng.randf())
					Figures.ellipse(self, at, 3.5, 3.0, col, 0.0, TAU, 8)
					draw_rect(Rect2(at + Vector2(-2, -2.2), Vector2(2, 1)), col.lightened(0.18))
		"p":
			draw_rect(r, GRASS.lerp(Color("3f6142"), n))
			for k in 6:
				var at := r.position + Vector2(rng.randf_range(2, 30), rng.randf_range(4, 30))
				draw_line(at, at + Vector2(rng.randf_range(-1.5, 1.5), -3), Color("4d7350"), 1)
			if rng.randf() < 0.12:
				draw_circle(r.position + Vector2(rng.randf_range(6, 26), rng.randf_range(6, 26)), 1.4, [Color("b8a65a"), Color("a9b4c8"), Color("c48a8a")][rng.randi() % 3])


# ------------------------------------------------------------- buildings

## One tile of a building: roof, or (on its bottom row) its front.
func _block(x: int, y: int) -> void:
	var c := _building(x, y)
	var r := Rect2(x * T, y * T, T, T)
	var front := _building(x, y + 1) != c and not (c == "W" and y == town.h - 1)
	var top := _building(x, y - 1) != c
	var left := _building(x - 1, y) != c
	var right := _building(x + 1, y) != c
	if c == "R":
		return  # (the rule wall is drawn whole, below)
	var roof := Color(ROOF[c])
	var face := Color(FRONT[c])
	if c == "Q":  # the old houses: each roof its own weathered tone
		roof = roof.lerp(Color("6e4636"), _hash(x / 3, y) * 0.8)
	if front and c != "W":
		_front(c, r, face, left, right, x, y)
		# the eaves: the roof's edge throws a line of shadow on the front
		draw_rect(Rect2(r.position, Vector2(T, 4)), roof.darkened(0.25))
		draw_rect(Rect2(r.position + Vector2(0, 4), Vector2(T, 2)), Color(0, 0, 0, 0.25))
		if top:  # a one-row building still shows a strip of roof
			draw_rect(Rect2(r.position, Vector2(T, 8)), roof)
			draw_rect(Rect2(r.position, Vector2(T, 2)), roof.lightened(0.22))
			draw_rect(Rect2(r.position + Vector2(0, 8), Vector2(T, 2)), Color(0, 0, 0, 0.3))
		return
	match c:
		"W":
			_wall(r, front, top, left, right, x, y)
			return
		"H", "#":  # flat concrete roofs: a parapet, gravel, a vent or a water tank
			draw_rect(r, roof.lerp(roof.lightened(0.06), _hash(x / 2, y)))
			# cast concrete panels, a stain or two, gravel
			draw_line(r.position + Vector2(0, 16), r.position + Vector2(T, 16), roof.darkened(0.1), 1)
			draw_line(r.position + Vector2(16, 0), r.position + Vector2(16, T), roof.darkened(0.1), 1)
			if _hash(x * 5, y + 9) < 0.3:
				Figures.ellipse(self, r.position + Vector2(rng.randf_range(8, 24), rng.randf_range(8, 24)), rng.randf_range(5, 10), rng.randf_range(3, 6), Color(0, 0, 0, 0.08))
			for k in 6:
				draw_rect(Rect2(r.position + Vector2(rng.randf_range(2, 28), rng.randf_range(2, 28)), Vector2(2, 2)), roof.lightened(0.1))
			if top and not left and _building(x - 2, y) == c and _building(x + 2, y) == c and _hash(x, y + 3) < 0.25:
				# a stair hut, with its door
				draw_rect(Rect2(r.position + Vector2(4, 8), Vector2(24, 18)), Color(0, 0, 0, 0.2))
				draw_rect(Rect2(r.position + Vector2(2, 4), Vector2(24, 18)), Color(FRONT[c]).darkened(0.1))
				draw_rect(Rect2(r.position + Vector2(2, 4), Vector2(24, 7)), roof.lightened(0.15))
				draw_rect(Rect2(r.position + Vector2(10, 12), Vector2(7, 10)), Color("3b3631"))
			elif _hash(x, y) < 0.12:
				draw_rect(Rect2(r.position + Vector2(8, 6), Vector2(14, 12)), roof.darkened(0.3))
				draw_rect(Rect2(r.position + Vector2(8, 6), Vector2(14, 9)), Color("6f7480"))
				draw_line(r.position + Vector2(9, 9), r.position + Vector2(21, 9), Color("5a5f6a"), 1)
			elif _hash(x + 7, y) < 0.15:
				draw_circle(r.position + Vector2(16, 14), 4, roof.darkened(0.35))
				draw_circle(r.position + Vector2(16, 13), 3, Color("767b86"))
		"F":  # the works: saw-tooth roofs of glass and tar, and chimneys
			draw_rect(r, roof)
			for k in 4:
				var yy := r.position.y + k * 8
				draw_rect(Rect2(r.position.x, yy, T, 5), roof.lightened(0.08))
				draw_rect(Rect2(r.position.x, yy + 5, T, 3), Color("6b7a88"))
			if (x % 6 == 3) and top:
				chimneys.append(r.position + Vector2(16, 2))
		"M":  # the ration hall: corrugated roof
			draw_rect(r, roof)
			for k in 8:
				draw_line(r.position + Vector2(k * 4 + 1, 0), r.position + Vector2(k * 4 + 1, T), roof.darkened(0.15), 1.5)
			draw_line(r.position + Vector2(0, 16), r.position + Vector2(T, 16), roof.lightened(0.1), 1)
		"B":
			draw_rect(r, roof)
			draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(T - 2, T - 2)), roof.lightened(0.04))
		"Q":  # terracotta tiles in rows, a ridge
			draw_rect(r, roof)
			for k in 5:
				var yy := r.position.y + 3 + k * 6
				draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), roof.darkened(0.2), 1.5)
				for j in 5:
					draw_line(Vector2(r.position.x + j * 7 + (k % 2) * 3, yy - 6), Vector2(r.position.x + j * 7 + (k % 2) * 3, yy), roof.darkened(0.12), 1)
			if top:
				draw_rect(Rect2(r.position, Vector2(T, 4)), roof.lightened(0.15))
			if _hash(x, y * 3) < 0.18 and top:
				chimneys.append(r.position + Vector2(10, 4))
	# rims: the roof's edge catches the light on its top and left
	if top:
		draw_rect(Rect2(r.position, Vector2(T, 3)), roof.lightened(0.22))
	if left:
		draw_rect(Rect2(r.position, Vector2(3, T)), roof.lightened(0.14))
	if right:
		draw_rect(Rect2(r.position + Vector2(T - 3, 0), Vector2(3, T)), roof.darkened(0.3))


## A building's front: one row of windows, now and then a door.
func _front(c: String, r: Rect2, face: Color, left: bool, right: bool, x: int, y: int) -> void:
	draw_rect(r, face)
	var door := _hash(x, y + 50) < 0.22 and not left and not right
	match c:
		"H", "#":  # flats: two windows, a plinth
			draw_rect(Rect2(r.position + Vector2(0, T - 5), Vector2(T, 5)), face.darkened(0.3))
			if door:
				_door(r, Color("3b3631"))
			else:
				for k in 2:
					_window(Rect2(r.position + Vector2(5 + k * 14, 10), Vector2(9, 11)), face, 0.3)
		"F":  # brick, with tall factory windows
			for k in 5:
				var yy := r.position.y + 7 + k * 5
				draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), face.darkened(0.18), 1)
			if door:
				draw_rect(Rect2(r.position + Vector2(4, 9), Vector2(24, 23)), Color("2e2c2b"))
				for k in 5:
					draw_line(r.position + Vector2(4, 12 + k * 4), r.position + Vector2(28, 12 + k * 4), Color("45423f"), 1)
			else:
				var wr := Rect2(r.position + Vector2(6, 9), Vector2(20, 16))
				_window(wr, face, 0.25)
				draw_line(wr.position + Vector2(10, 0), wr.position + Vector2(10, 16), face.darkened(0.3), 1)
				draw_line(wr.position + Vector2(0, 8), wr.position + Vector2(20, 8), face.darkened(0.3), 1)
		"M":  # the ration hall: a striped awning and shutters
			for k in 4:
				var a := Rect2(r.position + Vector2(k * 8, 6), Vector2(8, 7))
				draw_rect(a, Color("7d3434") if k % 2 == 0 else Color("d8cfb8"))
			draw_rect(Rect2(r.position + Vector2(0, 13), Vector2(T, 2)), Color(0, 0, 0, 0.3))
			if door:
				_door(r, Color("4a3a2c"))
			else:
				var sh := Rect2(r.position + Vector2(4, 16), Vector2(24, 13))
				draw_rect(sh, face.darkened(0.35))
				for k in 4:
					draw_line(sh.position + Vector2(0, 2 + k * 3), sh.position + Vector2(24, 2 + k * 3), face.darkened(0.2), 1)
		"B":  # the Bureau: dark columns, narrow windows, nobody inside you can see
			draw_rect(Rect2(r.position + Vector2(2, 6), Vector2(5, 26)), face.lightened(0.12))
			draw_rect(Rect2(r.position + Vector2(T - 7, 6), Vector2(5, 26)), face.lightened(0.06))
			draw_rect(Rect2(r.position + Vector2(12, 11), Vector2(8, 15)), Color("150b0d"))
			draw_rect(Rect2(r.position + Vector2(0, T - 4), Vector2(T, 4)), face.darkened(0.4))
		"Q":  # the old houses: plaster and timber, shuttered windows
			draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(T, 2)), Color("5c4434"))
			draw_rect(Rect2(r.position + Vector2(0, T - 3), Vector2(T, 3)), Color("5c4434"))
			if left:
				draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(3, T - 6)), Color("5c4434"))
			if right:
				draw_rect(Rect2(r.position + Vector2(T - 3, 6), Vector2(3, T - 6)), Color("4c3628"))
			if door:
				_door(r, Color("5a3a28"))
			else:
				var wr := Rect2(r.position + Vector2(11, 11), Vector2(10, 10))
				_window(wr, face, 0.45)
				draw_rect(Rect2(wr.position - Vector2(4, 0), Vector2(4, 10)), Color("4f6a5c"))
				draw_rect(Rect2(wr.position + Vector2(10, 0), Vector2(4, 10)), Color("4f6a5c"))
	if left:
		draw_rect(Rect2(r.position, Vector2(2, T)), face.lightened(0.12))
	if right:
		draw_rect(Rect2(r.position + Vector2(T - 2, 0), Vector2(2, T)), face.darkened(0.3))


func _window(wr: Rect2, face: Color, lit_chance: float) -> void:
	var lit := rng.randf() < lit_chance
	draw_rect(wr.grow(1.5), face.lightened(0.2))
	draw_rect(wr, LIT.darkened(0.25) if lit else DARK_GLASS)
	if lit:
		windows.append(wr)
		draw_rect(Rect2(wr.position, Vector2(wr.size.x, wr.size.y * 0.35)), LIT)
	else:
		draw_line(wr.position + Vector2(1, wr.size.y - 2), wr.position + Vector2(wr.size.x * 0.6, 2), Color(1, 1, 1, 0.12), 1)
	draw_rect(Rect2(wr.position + Vector2(-2, wr.size.y), Vector2(wr.size.x + 4, 2)), face.lightened(0.3))


func _door(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(9, 10), Vector2(14, 22)), face_dark(col))
	draw_rect(Rect2(r.position + Vector2(10, 11), Vector2(12, 21)), col)
	draw_circle(r.position + Vector2(19, 22), 1, Color("c8b070"))
	draw_rect(Rect2(r.position + Vector2(10, 11), Vector2(12, 4)), LIT.darkened(0.4))  # a fanlight


func face_dark(c: Color) -> Color:
	return c.darkened(0.4)


func _wall(r: Rect2, front: bool, top: bool, left: bool, right: bool, x: int, y: int) -> void:
	var roof := Color(ROOF.W)
	var face := Color(FRONT.W)
	if front:
		# the inner face of the north wall: big stone blocks
		draw_rect(r, face)
		for j in 3:
			var off := 8.0 if j % 2 == 1 else 0.0
			for k in 3:
				var b := Rect2(r.position + Vector2(k * 16 - off, 6 + j * 9), Vector2(15, 8))
				b = b.intersection(r)
				if b.size.x > 1:
					draw_rect(b, face.lerp(Color("67656b"), _hash(x * 3 + k, j + y * 5)))
		draw_rect(Rect2(r.position, Vector2(T, 6)), roof)
		return
	draw_rect(r, roof)
	# the walk along the top and its battlements, on the town's side
	draw_rect(r.grow(-6), roof.darkened(0.12))
	for k in 2:
		var m := Rect2(r.position + Vector2(2 + k * 16, 2), Vector2(11, 6))
		if y == town.h - 1:
			m.position.y = r.position.y + 2
		elif x == 0:
			m = Rect2(r.position + Vector2(2, 2 + k * 16), Vector2(6, 11))
		elif x == town.w - 1:
			m = Rect2(r.position + Vector2(T - 8, 2 + k * 16), Vector2(6, 11))
		draw_rect(m, roof.lightened(0.15))
		draw_rect(Rect2(m.position + Vector2(0, m.size.y - 1.5), Vector2(m.size.x, 1.5)), roof.darkened(0.3))


func _rule_wall() -> void:
	# the rule wall in the square: a board on posts, plastered with notices
	var cells := []
	for y in town.h:
		for x in town.w:
			if town.tile(x, y) == "R":
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return
	var a := Vector2(cells[0].x * T, cells[0].y * T)
	var b := Vector2((cells[-1].x + 1) * T, (cells[-1].y + 1) * T)
	var r := Rect2(a, b - a)
	draw_rect(Rect2(r.position + Vector2(4, r.size.y - 2), Vector2(r.size.x - 8, 6)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(r.position + Vector2(6, 18), Vector2(5, 14)), Color("2c2622"))
	draw_rect(Rect2(r.end - Vector2(11, 14), Vector2(5, 14)), Color("2c2622"))
	var board := Rect2(r.position + Vector2(0, -14), Vector2(r.size.x, 40))
	draw_rect(board.grow(2), Color("1d1a18"))
	draw_rect(board, Color(FRONT.R))
	var notes := [Color("e8e1cf"), Color("d9d1bb"), Color("efe6cc")]
	for k in 5:
		var n := Rect2(board.position + Vector2(6 + k * 24, 6 + (k % 2) * 3), Vector2(19, 25))
		draw_rect(n, notes[k % 3])
		draw_rect(Rect2(n.position + Vector2(3, 3), Vector2(13, 3)), Color("a81f30"))
		for j in 4:
			draw_line(n.position + Vector2(3, 10 + j * 3.5), n.position + Vector2(16 - (j % 2) * 4, 10 + j * 3.5), Color("8a8478"), 1)
	draw_string(wall_font, board.position + Vector2(0, -6), "THE RULES", HORIZONTAL_ALIGNMENT_CENTER, board.size.x, 18, Color("e8e1cf"))


func _bureau() -> void:
	# a red banner down the Bureau's roof, and its eye
	var d: Rect2i = town.districts.bureau
	var cells := Rect2()
	var first := true
	for y in town.h:
		for x in town.w:
			if town.tile(x, y) == "B":
				var c := Rect2(x * T, y * T, T, T)
				cells = c if first else cells.merge(c)
				first = false
	if first:
		return
	var mid := cells.position.x + cells.size.x / 2
	var banner := Rect2(mid - 42, cells.position.y + 6, 84, cells.size.y - T - 10)
	draw_rect(banner.grow(3), Color("1b1214"))
	draw_rect(banner, Color("9e2030"))
	draw_rect(Rect2(banner.position, Vector2(banner.size.x, 6)), Color("b8293b"))
	for k in 2:  # its folds
		draw_line(banner.position + Vector2(28 + k * 28, 6), banner.position + Vector2(28 + k * 28, banner.size.y), Color(0, 0, 0, 0.18), 2)
	eye = Vector2(mid, banner.position.y + banner.size.y * 0.42)
	var pts := PackedVector2Array()
	for i in 25:
		var a := PI * i / 12.0
		pts.append(eye + Vector2(cos(a) * 30, sin(a) * 15))
	draw_colored_polygon(pts, Color("e8e1cf").darkened(0.15))
	draw_circle(eye, 12, Color("1a0c0d"))
	draw_circle(eye, 5, Color("e0384a"))
	draw_circle(eye + Vector2(-3, -3), 2, Color(1, 1, 1, 0.6))
	draw_string(wall_font, Vector2(banner.position.x, banner.end.y - 14), "THE BUREAU", HORIZONTAL_ALIGNMENT_CENTER, banner.size.x, 16, Color("e8e1cf"))
	# the steps up to its doors
	var steps := Rect2(mid - 48, cells.end.y, 96, 10)
	for k in 3:
		draw_rect(Rect2(steps.position + Vector2(-k * 4, k * 3), Vector2(steps.size.x + k * 8, 3)), Color("6a6066").darkened(k * 0.12))
	draw_rect(Rect2(mid - 16, cells.end.y - 26, 32, 26), Color("150b0d"))


func _tree(c: Vector2) -> void:
	Figures.ellipse(self, c + Vector2(8, 12), 17, 8, Color(0, 0, 0, 0.3))
	draw_rect(Rect2(c + Vector2(-2.5, 0), Vector2(5, 12)), Color("3e2f24"))
	var leaf := Color("2f4d33")
	draw_circle(c + Vector2(0, -6), 16, Color("1b2a1d"))
	for k in 5:
		var a := TAU * k / 5.0 + _hash(int(c.x), int(c.y))
		draw_circle(c + Vector2(cos(a) * 7, sin(a) * 6 - 6), 9.5, leaf)
	draw_circle(c + Vector2(-4, -10), 9, leaf.lightened(0.12))
	draw_circle(c + Vector2(-6, -13), 5, leaf.lightened(0.25))


func _lamp_post(p: Vector2) -> void:
	var base := p + Vector2(10, 10)
	Figures.ellipse(self, base + Vector2(3, 2), 6, 2.5, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(base + Vector2(-1.5, -30), Vector2(3, 30)), Color("23252b"))
	draw_rect(Rect2(base + Vector2(-3, -3), Vector2(6, 3)), Color("23252b"))
	draw_line(base + Vector2(0, -30), base + Vector2(-8, -32), Color("23252b"), 2)
	draw_rect(Rect2(base + Vector2(-13, -33), Vector2(9, 4)), Color("2c2f36"))
	draw_rect(Rect2(base + Vector2(-12, -30), Vector2(7, 2)), Color("ffd690"))


func _exits() -> void:
	for e in town.exits:
		var r := Rect2(e.x * T, e.y * T, T, T)
		if town.tile(e.x, e.y) == "G":
			# the gate: iron bars in a stone arch
			draw_rect(r, Color("1d1e22"))
			for k in 5:
				draw_rect(Rect2(r.position + Vector2(3 + k * 6, 2), Vector2(2, 28)), Color("6a6e78"))
			draw_rect(Rect2(r.position + Vector2(0, 8), Vector2(T, 2)), Color("6a6e78"))
		else:
			# the culvert: a dark mouth in the wall, half hidden by a grate
			draw_rect(r, Color("0c0d0f"))
			Figures.ellipse(self, r.position + Vector2(16, 18), 12, 12, Color("070708"))
			for k in 4:
				draw_line(r.position + Vector2(6, 9 + k * 6), r.position + Vector2(26, 9 + k * 6), Color("3a3d42"), 2)


func _names() -> void:
	# district names on the ground, for finding your way
	for k in town.districts:
		var d: Rect2i = town.districts[k]
		var name: String = town.names[k].to_upper().replace("THE ", "")
		var at := Vector2(d.position.x * T + 8, d.position.y * T + 24)
		if k == "square":
			at = Vector2(d.position.x * T + 8, d.end.y * T - 12)
		draw_string_outline(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.45))
		draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.92, 0.88, 0.78, 0.6))


func _hash(a: int, b: int) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)
