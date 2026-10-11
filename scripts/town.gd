class_name Town
extends RefCounted
## The town (data/town.json, from tools/make_town.py): which tiles are solid,
## where the districts are, the doors people walk between, the street lamps,
## and paths across it (AStarGrid2D). One shared copy: Town.get_town().

const TILE := 32
const SOLID := "W#HFMBQRT"
const EXITS := "GC"

static var _town: Town

var w := 0
var h := 0
var rows: Array = []
var districts := {}  # name -> Rect2i (tiles)
var names := {}      # name -> "the Old Quarter"
var doors := {}      # district -> Array[Vector2] (world positions on the street beside a building)
var lamps: Array[Vector2] = []
var exits: Array[Vector2i] = []
var astar := AStarGrid2D.new()
var walkable: Array[Vector2i] = []


static func get_town() -> Town:
	if _town == null:
		_town = Town.new()
		_town._load()
	return _town


func _load() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/town.json"))
	w = int(d.w)
	h = int(d.h)
	rows = d.rows
	names = d.names
	for k in d.districts:
		var r: Array = d.districts[k]
		districts[k] = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE / 2.0, TILE / 2.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in h:
		for x in w:
			var c := tile(x, y)
			astar.set_point_solid(Vector2i(x, y), c in SOLID)
			if not c in SOLID:
				walkable.append(Vector2i(x, y))
			if c in EXITS:
				exits.append(Vector2i(x, y))
	# doors: street tiles beside a building, sorted by district
	for k in districts:
		doors[k] = []
	for p in walkable:
		if tile(p.x, p.y) in EXITS:
			continue
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c := tile(p.x + n.x, p.y + n.y)
			if c in "HFMBQ":
				var k := district_of_tile(p)
				if k != "":
					doors[k].append(centre(p))
				break
	# street lamps: every few tiles along the streets, never on the paving's trees
	for p in walkable:
		var c := tile(p.x, p.y)
		if (c == "." or c == "o") and (p.x * 7 + p.y * 13) % 23 == 0:
			lamps.append(centre(p))


func tile(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return "W"
	return rows[y][x]


func solid_at(pos: Vector2) -> bool:
	return tile(int(floor(pos.x / TILE)), int(floor(pos.y / TILE))) in SOLID


func cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


static func centre(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)


func district_of_tile(c: Vector2i) -> String:
	for k in districts:
		if districts[k].has_point(c):
			return k
	return ""


func district_at(pos: Vector2) -> String:
	return district_of_tile(cell(pos))


func is_exit(pos: Vector2) -> bool:
	return tile(cell(pos).x, cell(pos).y) in EXITS


## A path of world points from a to b (empty if there's none).
func path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var from := cell(a)
	var to := cell(b)
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return PackedVector2Array()
	return astar.get_point_path(from, to, true)


## Move a body of radius r by d, sliding along walls (each axis on its own).
func slide(pos: Vector2, d: Vector2, r := 7.0) -> Vector2:
	var p := pos
	var nx := Vector2(p.x + d.x, p.y)
	if not _hits(nx, r):
		p = nx
	var ny := Vector2(p.x, p.y + d.y)
	if not _hits(ny, r):
		p = ny
	return p


func _hits(p: Vector2, r: float) -> bool:
	for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		if solid_at(p + o):
			return true
	return false


func random_walkable(rng: RandomNumberGenerator, in_district := "") -> Vector2:
	for i in 200:
		var c: Vector2i = walkable[rng.randi() % walkable.size()]
		if tile(c.x, c.y) in EXITS:
			continue
		if in_district == "" or district_of_tile(c) == in_district:
			return centre(c)
	return centre(walkable[0])
