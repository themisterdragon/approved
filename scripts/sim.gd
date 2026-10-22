class_name Sim
extends RefCounted
## One round of Approved, run by the host. A crowd of townsfolk keeps the
## Bureau's rules as the wall reads now; the citizens (players) hide among
## them, gather torn pages and slip out through the gate or the culvert. The
## ruler watches through a few cameras and may have people taken for
## questioning. Everything that happens goes in the log for the debrief.
## Views never touch this directly: they read snapshot_for().

# what a person is doing, as bits in snapshots
const B_MOVING := 1
const B_HURRY := 2
const B_SEARCH := 4
const B_NOD := 8
const B_HIDDEN := 16
# why a person stands out (the ruler sees these on camera)
const F_CURFEW := 1
const F_HURRY := 2
const F_LINGER := 4
const F_GATHER := 8
const F_CLOSED := 16
const F_POST := 32
const F_WALL := 64
const F_SEARCH := 128
const F_NOD := 256
const FLAG_NAMES := {F_CURFEW: "out after curfew", F_HURRY: "hurrying", F_LINGER: "lingering",
	F_GATHER: "gathering", F_CLOSED: "in a closed district", F_POST: "away from their post",
	F_WALL: "at the wall", F_SEARCH: "searching the ground", F_NOD: "signalling"}

const WALK := 44.0
const HURRY := 1.8
const CAM_R := 150.0
const CAM_MOVE := 6.0      # seconds a camera is blind while it's moved
const PAGES_NEEDED := 3
const ESCAPE_TIME := 6.0
const SEARCH_TIME := 2.5
const NPCS := 36
const LOOKS := 12  # kinds of people (scripts/figures.gd)
const WALL_AT := Vector2(960, 432)  # the rule wall in Assembly Square
const WALL_READ := 130.0

var town := Town.get_town()
var rng := RandomNumberGenerator.new()
var people: Array = []
var cams: Array = []    # {pos, owner, blind}
var pages: Array = []   # Vector2: torn pages lying about
var rules := {}         # rule -> wording (variant)
var rules_start := {}
var length := 420.0
var t := 0.0
var over := false
var warrants := 3
var warrant_t := 0.0
var amend_wait := 0.0
var unrest := 0
var events: Array = []     # {t, text, kind, public}
var questions: Array = []
var ruler_bot := false
var council := 1
var bot_t := 0.0
var bell := false
var bell_since := 0.0
var _gather_t := 0.0
var page_cap := 0
var page_t := 0.0
const PAGE_EVERY := 25.0


## cfg: {length, citizens: [{peer, bot}], ruler_bot, council, rules, questions, seed}
func setup(cfg: Dictionary) -> void:
	rng.seed = int(cfg.get("seed", Time.get_ticks_usec()))
	length = float(cfg.get("length", 420.0))
	ruler_bot = bool(cfg.get("ruler_bot", false))
	council = int(cfg.get("council", 1))
	questions = cfg.get("questions", [])
	rules = (cfg.get("rules", Rules.DEFAULT) as Dictionary).duplicate()
	rules_start = rules.duplicate()
	_apply_rules()
	warrants = 2 + council
	var cits: Array = cfg.get("citizens", [])
	var n := NPCS + cits.size()
	var slots := range(n)
	slots.shuffle()  # (people are in a random order, so a number gives nothing away)
	people.resize(n)
	var used_nums := {}
	for i in n:
		var p := {"pos": town.random_walkable(rng, "housing" if rng.randf() < 0.4 else ""), "look": rng.randi() % LOOKS,
			"kind": "npc", "bits": 0, "flags": 0, "sus": 0.0, "seen": false, "path": PackedVector2Array(), "pi": 0,
			"wait": rng.randf() * 4.0, "idle": 0.0, "near_t": 0.0, "hidden": "", "nod_t": 0.0,
			"home": _door("housing"), "job": _door("works"), "permit": rng.randf() < 0.15}
		people[i] = p
	for j in cits.size():
		var p: Dictionary = people[slots[j]]
		var num := 0
		while num == 0 or used_nums.has(num):
			num = 1000 + rng.randi() % 9000
		used_nums[num] = true
		p.merge({"kind": "cit", "peer": cits[j].get("peer", ""), "bot": bool(cits[j].get("bot", false)), "num": num,
			"pages": 0, "inp": {}, "search_t": 0.0, "esc_t": 0.0, "msg": "", "msg_t": 0.0, "wall": [], "wall_t": -1.0,
			"q": {}, "q_t": 0.0, "q_wait": 0.0, "q_right": 0,
			"stats": {"pages": 0, "nods": 0, "gives": 0, "taken": 0, "seen": 0.0, "escaped": false}}, true)
		p.wall = Rules.wall_lines(rules)  # everyone starts knowing the rules as first posted
		p.wall_t = 0.0
	# pages are scarce at dawn and turn up through the day: three each is
	# more than there are at first, so passing them on matters
	for i in cits.size() + 2:
		pages.append(_page_spot())
	page_cap = cits.size() * 3
	if ruler_bot:
		_bot_cameras()
	else:
		# the ruler moves these; they start spread over the town
		var spots := [WALL_AT + Vector2(0, 90), Vector2(1450, 560), Vector2(330, 300), Vector2(1400, 220), Vector2(960, 900), Vector2(500, 760)]
		for i in 3 + council:
			cams.append({"pos": spots[i % spots.size()], "owner": i % council, "blind": 0.0})
	_say(0, "The Bureau has posted the rules: " + " ".join(Rules.wall_lines(rules)), "rules", true)


func _door(district: String) -> Vector2:
	var d: Array = town.doors.get(district, [])
	return d[rng.randi() % d.size()] if d.size() > 0 else town.random_walkable(rng, district)


## Pages turn up in out-of-the-way places: the old quarter, the gardens,
## the lanes behind the housing.
func _page_spot() -> Vector2:
	var where := ["old", "old", "park", "housing", "market", "works"]
	return town.random_walkable(rng, where[rng.randi() % where.size()]) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))


func _say(time: float, text: String, kind: String, public: bool) -> void:
	events.append({"t": snappedf(time, 0.1), "text": text, "kind": kind, "public": public, "id": events.size()})


# ------------------------------------------------------------------ rules

## The townsfolk keep away from a closed district.
func _apply_rules() -> void:
	var closed := closed_district()
	for c in town.walkable:
		town.astar.set_point_weight_scale(c, 25.0 if closed != "" and town.district_of_tile(c) == closed else 1.0)


func closed_district() -> String:
	if not rules.has("closed"):
		return ""
	return Rules.CARDS.closed.districts[int(rules.closed)]


func dusk_at() -> float:
	if rules.has("curfew") and int(rules.curfew) == 1:
		return length * 0.5
	return length * 0.65


func is_night() -> bool:
	return t >= dusk_at()


func amend(rule: String, variant: int, who := "The Bureau") -> bool:
	if not rules.has(rule) or amend_wait > 0 or int(rules[rule]) == variant:
		return false
	var before := Rules.text(rule, int(rules[rule]))
	rules[rule] = variant
	amend_wait = Rules.AMEND_EVERY
	_apply_rules()
	for p in people:
		if p.kind == "npc":
			p.path = PackedVector2Array()  # the townsfolk obey at once
	_say(t, "%s amended the wall. \"%s\" now reads \"%s\"" % [who, before, Rules.text(rule, variant)], "amend", false)
	_say(t, "Workers repainted part of the wall in Assembly Square.", "amend_public", true)
	return true


# ------------------------------------------------------------------- step

func step(dt: float) -> void:
	if over:
		return
	t += dt
	amend_wait = maxf(amend_wait - dt, 0)
	warrant_t += dt
	if warrant_t >= 90.0:
		warrant_t = 0
		warrants = mini(warrants + 1, 6)
	var was_night := t - dt >= dusk_at()
	if is_night() and not was_night:
		_say(t, "Dusk. The lamps come on." + (" Curfew." if rules.has("curfew") else ""), "dusk", true)
	_bell()
	page_t += dt
	if page_t >= PAGE_EVERY:
		page_t = 0
		var held := 0
		for p in people:
			if p.kind == "cit":
				held += int(p.get("pages", 0))
		if pages.size() + held < page_cap:
			pages.append(_page_spot())
	for c in cams:
		c.blind = maxf(c.blind - dt, 0)
	for p in people:
		if p.hidden != "":
			if p.kind == "cit" and p.hidden == "taken":
				_questioning(p, dt)
			continue
		if p.kind == "npc":
			_npc(p, dt)
		else:
			if p.bot:
				_bot_citizen(p)
			_citizen(p, dt)
		p.nod_t = maxf(p.nod_t - dt, 0)
	_gather_t += dt
	if _gather_t >= 0.25:
		_gathering(_gather_t)
		_gather_t = 0
	_flags_and_eyes(dt)
	if ruler_bot:
		_bot_ruler(dt)
	var left := 0
	for p in people:
		if p.kind == "cit" and (p.hidden == "" or p.hidden == "taken"):
			left += 1
	if t >= length or left == 0:
		over = true
		_say(t, "The day is over.", "end", true)


func _bell() -> void:
	var on := false
	if rules.has("posts") and t > 30:
		on = fmod(t - 30, Rules.BELL_EVERY) < Rules.BELL_LONG
	if on and not bell:
		bell_since = t
		_say(t, "The bell rings. To your posts.", "bell", true)
		for p in people:
			if p.kind == "npc":
				p.path = PackedVector2Array()
				p.wait = 0
	bell = on


## Where the post is for this bell, by the wall's wording.
func post_district() -> String:
	return "works" if int(rules.get("posts", 0)) == 0 else "square"


# ------------------------------------------------------------- townsfolk

func _npc(p: Dictionary, dt: float) -> void:
	if p.path.is_empty() or p.pi >= p.path.size():
		p.bits &= ~B_MOVING
		p.wait -= dt
		p.idle += dt
		if p.wait <= 0:
			if p.get("going_home", false):
				p.hidden = "home"  # in for the night
				return
			_npc_go(p)
		return
	var target: Vector2 = p.path[p.pi] + p.get("jit", Vector2.ZERO)
	var d: Vector2 = target - p.pos
	var step := WALK * dt
	if d.length() <= step:
		p.pos = target
		p.pi += 1
		if p.pi >= p.path.size():
			var linger_banned: bool = rules.has("walk") and int(rules.walk) == 1
			p.wait = rng.randf_range(0.3, 0.8) if linger_banned else rng.randf_range(2.0, 7.0)
	else:
		p.pos += d.normalized() * step
	p.bits |= B_MOVING
	p.idle = 0


func _npc_go(p: Dictionary) -> void:
	var dest: Vector2
	var curfew_on := rules.has("curfew") and is_night()
	var night_shift := curfew_on and int(rules.curfew) == 2
	p.going_home = false
	if curfew_on and not p.permit:
		if night_shift and town.district_at(p.job) == "works" and p.look % 2 == 0:
			dest = _door("works")  # the night shift
		else:
			dest = p.home
			p.going_home = true
	elif bell and rules.has("posts"):
		dest = _door("works") if post_district() == "works" else town.random_walkable(rng, "square")
	else:
		var closed := closed_district()
		var choice := ["market", "market", "works", "works", "square", "square", "park", "housing", "housing", "old"]
		var k: String = choice[rng.randi() % choice.size()]
		while k == closed:
			k = choice[rng.randi() % choice.size()]
		dest = _door(k) if town.doors.get(k, []).size() > 0 and rng.randf() < 0.7 else town.random_walkable(rng, k)
	p.path = town.path(p.pos, dest)
	p.pi = 1
	p.jit = Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
	if p.path.size() < 2:
		p.path = PackedVector2Array()
		p.wait = 1.0


# --------------------------------------------------------------- citizens

## inp: {mv: [x, y] (a direction), to: [x, y] (walk there), hurry, nod, give, ans}
func input(peer: String, inp: Dictionary) -> void:
	for p in people:
		if p.kind == "cit" and p.peer == peer:
			for k in inp:
				p.inp[k] = inp[k]
			return


func _citizen(p: Dictionary, dt: float) -> void:
	var inp: Dictionary = p.inp
	p.msg_t = maxf(p.msg_t - dt, 0)
	var mv := Vector2.ZERO
	if inp.has("mv") and inp.mv is Array:
		mv = Vector2(float(inp.mv[0]), float(inp.mv[1])).limit_length(1.0)
	if inp.has("to") and inp.to is Array:
		p.path = town.path(p.pos, Vector2(float(inp.to[0]), float(inp.to[1])))
		p.pi = 1
		inp.erase("to")
	if mv.length() > 0.1:
		p.path = PackedVector2Array()
	elif p.pi < p.path.size():
		var d: Vector2 = p.path[p.pi] - p.pos
		if d.length() < 4:
			p.pi += 1
		mv = d.normalized()
	var hurry: bool = inp.get("hurry", false) and mv.length() > 0.1
	var before: Vector2 = p.pos
	p.pos = town.slide(p.pos, mv * WALK * (HURRY if hurry else 1.0) * dt)
	var moved: bool = p.pos.distance_to(before) > 0.2
	p.bits = (B_MOVING if moved else 0) | (B_HURRY if hurry and moved else 0)
	p.idle = 0.0 if moved else p.idle + dt
	# searching: stand over a page to pick it up
	var near := -1
	for i in pages.size():
		if pages[i].distance_to(p.pos) < 16:
			near = i
	if near >= 0 and not moved:
		p.search_t += dt
		p.bits |= B_SEARCH
		if p.search_t >= SEARCH_TIME:
			pages.remove_at(near)
			p.pages += 1
			p.stats.pages += 1
			p.search_t = 0
			_tell(p, "You found a torn page (%d of %d)." % [p.pages, PAGES_NEEDED])
	else:
		p.search_t = 0
	if inp.get("nod", false):
		inp.erase("nod")
		p.nod_t = 1.5
		p.stats.nods += 1
		if p.seen:
			p.sus = minf(p.sus + 12, 100)
	if inp.get("give", false):
		inp.erase("give")
		_give(p)
	# reading the wall: close enough to the wall, you know what it says now
	if p.pos.distance_to(WALL_AT) < WALL_READ:
		var now := Rules.wall_lines(rules)
		if now != p.wall:
			p.wall = now
			_tell(p, "You read the wall. Something has changed.")
		p.wall_t = t
	# the way out
	if town.is_exit(p.pos):
		if p.pages < PAGES_NEEDED:
			if p.msg_t <= 0:
				_tell(p, "You need %d torn pages to find the way out." % PAGES_NEEDED)
		elif p.seen:
			p.esc_t = 0
		else:
			p.esc_t += dt
			if p.esc_t >= ESCAPE_TIME:
				p.hidden = "gone"
				p.stats.escaped = true
				_say(t, "Citizen %d slipped out of the town." % p.num, "escape", false)
				_say(t, "Someone is missing from the evening count.", "escape_public", true)
	else:
		p.esc_t = 0


## A player's screen closed: they leave the game (not counted either way).
func leave(peer: String) -> void:
	for p in people:
		if p.kind == "cit" and p.peer == peer and p.hidden != "gone":
			p.hidden = "left"
			_say(t, "Citizen %d left the game." % p.num, "left", false)


func _tell(p: Dictionary, text: String) -> void:
	p.msg = text
	p.msg_t = 4.0


## Hand a page to whoever is beside you. A fellow citizen takes it; one of
## the townsfolk looks away (and a camera may have seen you try).
func _give(p: Dictionary) -> void:
	if p.pages <= 0:
		_tell(p, "You have no pages to pass on.")
		return
	var best = null
	var bd := 30.0
	for o in people:
		if o != p and o.hidden == "" and o.pos.distance_to(p.pos) < bd:
			best = o
			bd = o.pos.distance_to(p.pos)
	if best == null:
		_tell(p, "No one is close enough.")
		return
	if p.seen:
		p.sus = minf(p.sus + 25, 100)
	if best.kind == "cit":
		p.pages -= 1
		best.pages += 1
		p.stats.gives += 1
		_tell(p, "You passed a page. They didn't look up.")
		_tell(best, "Someone pressed a torn page into your hand (%d of %d)." % [best.pages, PAGES_NEEDED])
		_say(t, "Citizen %d passed a page to Citizen %d." % [p.num, best.num], "give", false)
	else:
		_tell(p, "They look away, and walk on a little faster.")
		_say(t, "Citizen %d tried to pass a page to a stranger." % p.num, "give_fail", false)


# -------------------------------------------------------------- the eyes

func _gathering(dt: float) -> void:
	if not rules.has("gather"):
		return
	var pairs := int(rules.gather) == 1
	for p in people:
		if p.hidden != "":
			continue
		var n := 0
		for o in people:
			if o != p and o.hidden == "" and o.pos.distance_squared_to(p.pos) < (26.0 * 26.0 if pairs else 36.0 * 36.0):
				n += 1
		var bad: bool = (n >= 1 and (int(p.bits) & B_MOVING) != 0) if pairs else n >= 2
		p.near_t = p.near_t + dt if bad else 0.0


func _flags_and_eyes(dt: float) -> void:
	var closed := closed_district()
	var curfew := rules.has("curfew") and is_night()
	for p in people:
		if p.hidden != "":
			p.seen = false
			continue
		var f := 0
		var where := town.district_at(p.pos)
		if curfew and where != "housing" and not (p.kind == "npc" and p.permit):
			if not (int(rules.curfew) == 2 and where == "works"):
				f |= F_CURFEW
		if rules.has("walk"):
			if int(rules.walk) == 0 and p.bits & B_HURRY:
				f |= F_HURRY
			if int(rules.walk) == 1 and p.idle > 4.0:
				f |= F_LINGER
		if p.near_t > (1.5 if int(rules.get("gather", 0)) == 1 else 2.0):
			f |= F_GATHER
		if closed != "" and where == closed:
			f |= F_CLOSED
		if bell and t - bell_since > Rules.BELL_GRACE and where != post_district():
			f |= F_POST
		if town.is_exit(p.pos):
			f |= F_WALL
		if p.bits & B_SEARCH:
			f |= F_SEARCH
		if p.nod_t > 0:
			f |= F_NOD
		p.flags = f
		p.seen = false
		for c in cams:
			if c.blind <= 0 and c.pos.distance_squared_to(p.pos) < CAM_R * CAM_R:
				p.seen = true
				break
		if p.seen:
			if p.kind == "cit":
				p.stats.seen += dt
			var bad := 0
			for b in [F_CURFEW, F_HURRY, F_LINGER, F_GATHER, F_CLOSED, F_POST, F_WALL]:
				if f & b:
					bad += 1
			p.sus = minf(p.sus + dt * (30.0 * bad + (45.0 if f & F_SEARCH else 0.0)), 100)
		if not p.seen or f == 0:
			p.sus = maxf(p.sus - dt * 3.0, 0)


# ------------------------------------------------------------- the ruler

func move_camera(i: int, pos: Vector2, owner := -1) -> bool:
	if i < 0 or i >= cams.size() or (owner >= 0 and cams[i].owner != owner):
		return false
	if town.solid_at(pos):
		return false
	cams[i].pos = pos
	cams[i].blind = CAM_MOVE
	return true


## Have a person taken. Only someone a camera sees right now, and only
## while there are warrants left.
func detain(i: int, who := "The Bureau") -> bool:
	if i < 0 or i >= people.size() or warrants <= 0:
		return false
	var p: Dictionary = people[i]
	if p.hidden != "" or not p.seen:
		return false
	warrants -= 1
	var why := _why(p.flags)
	if p.kind == "npc":
		p.hidden = "taken"
		unrest += 1
		_say(t, "%s had an innocent person taken%s." % [who, " (" + why + ")" if why != "" else ""], "innocent", false)
		_say(t, "A neighbour was taken for questioning.", "taken_public", true)
	else:
		p.hidden = "taken"
		p.stats.taken += 1
		var lost: int = p.pages
		for k in lost:
			pages.append(_page_spot())
		p.pages = 0
		p.q_t = 0.0
		p.q_wait = 15.0
		p.q_right = 0
		p.q = _question()
		p.path = PackedVector2Array()
		_say(t, "%s had Citizen %d taken for questioning%s.%s" % [who, p.num, " (" + why + ")" if why != "" else "",
			" %d pages confiscated." % lost if lost > 0 else ""], "taken", false)
		_say(t, "A neighbour was taken for questioning.", "taken_public", true)
	return true


func _why(f: int) -> String:
	var out := []
	for b in FLAG_NAMES:
		if f & b:
			out.append(FLAG_NAMES[b])
	return ", ".join(out)


# ---------------------------------------------------------- questioning

func _question() -> Dictionary:
	if questions.is_empty():
		return {"q": "Do you love order?", "answers": ["Yes", "Always", "More than anything", "With all my heart"], "correct": -1}
	var src: Dictionary = questions[rng.randi() % questions.size()]
	var answers: Array = [src.answer] + src.wrong
	answers.shuffle()
	return {"q": src.q, "answers": answers, "correct": answers.find(src.answer)}


## Answer two questions right and wait out your time, and you're let go,
## without your pages, and remembered.
func _questioning(p: Dictionary, dt: float) -> void:
	p.q_t += dt
	var a := int(p.inp.get("ans", -1))
	if p.bot and p.q_t > 4.0 and int(p.q_t * 10) % 40 == 0:
		a = p.q.correct if rng.randf() < 0.7 else rng.randi() % 4
	if a >= 0:
		p.inp.erase("ans")
		if a == p.q.correct or p.q.correct < 0:
			p.q_right += 1
			_tell(p, "\"Correct,\" says the clerk, and writes something down.")
		else:
			p.q_wait += 8.0
			_tell(p, "The clerk sighs. \"Again.\" (+8 seconds)")
		p.q = _question()
	if p.q_right >= 2 and p.q_t >= p.q_wait:
		p.hidden = ""
		p.pos = _door("housing")
		p.sus = 35.0
		p.inp = {}
		_tell(p, "You are released. They know your face now.")
		_say(t, "Citizen %d was released." % p.num, "released", false)


# ------------------------------------------------------------------ bots

func _bot_cameras() -> void:
	var spots := [Vector2(960, 1010), Vector2(160, 920), WALL_AT + Vector2(0, 80), Vector2(1400, 560), Vector2(600, 300)]
	for i in spots.size():
		cams.append({"pos": spots[i], "owner": 0, "blind": 0.0})


var _bot_cam_i := 0


func _bot_ruler(dt: float) -> void:
	bot_t += dt
	for i in people.size():
		var p: Dictionary = people[i]
		if p.seen and p.sus >= 65 and warrants > 0:
			detain(i, "The Bureau")
	if bot_t >= 22.0:
		bot_t = 0
		# move a camera (not the gate's) toward someone who stood out
		var hot := []
		for p in people:
			if p.hidden == "" and p.flags & ~(F_NOD | F_SEARCH) and p.flags != 0:
				hot.append(p.pos)
		_bot_cam_i = 2 + posmod(_bot_cam_i - 1, cams.size() - 2)
		var to: Vector2 = hot[rng.randi() % hot.size()] if hot.size() > 0 else town.random_walkable(rng)
		move_camera(_bot_cam_i, to)
		if rng.randf() < 0.3 and amend_wait <= 0 and rules.size() > 0:
			var r: String = rules.keys()[rng.randi() % rules.size()]
			amend(r, (int(rules[r]) + 1) % Rules.CARDS[r].texts.size())


## A robot citizen plays like a person: it wanders like the townsfolk,
## notices a page only when it's close (as a player would), keeps the
## rules it knows (mostly), and makes for the nearest way out with three.
func _bot_citizen(p: Dictionary) -> void:
	p.inp.hurry = (rng.randf() < 0.003) or (p.inp.get("hurry", false) and rng.randf() < 0.97)
	if p.bits & B_SEARCH:
		return
	var goal = null
	if p.pages >= PAGES_NEEDED:
		if rules.has("curfew") and is_night() and rng.randf() < 0.5:
			goal = null  # some wait for a quieter moment
		var best := INF
		for e in town.exits:
			var d: float = Town.centre(e).distance_to(p.pos)
			if d < best:
				best = d
				goal = Town.centre(e)
	else:
		var best := 230.0
		for g in pages:
			var d: float = g.distance_to(p.pos)
			if d < best:
				best = d
				goal = g
	if goal != null:
		if p.get("bot_goal", Vector2.INF) != goal and p.pos.distance_to(goal) > 6:
			p.bot_goal = goal
			p.inp.to = [goal.x, goal.y]
	elif p.pi >= p.path.size():
		# wander somewhere, like everyone else
		var where := ["old", "park", "market", "housing", "works", "square"]
		var to := town.random_walkable(rng, where[rng.randi() % where.size()])
		p.bot_goal = to
		p.inp.to = [to.x, to.y]


# ------------------------------------------------------------- snapshots

## What one screen needs. role: "ruler" (council seat `seat`), "citizen"
## (`peer`), or "public" (the shared screen).
func snapshot_for(role: String, peer := "", seat := 0) -> Dictionary:
	var flat := []
	for p in people:
		flat.append_array([roundi(p.pos.x), roundi(p.pos.y), p.look, p.bits | (B_HIDDEN if p.hidden != "" else 0) | (B_NOD if p.nod_t > 0 else 0)])
	var s := {"k": "s", "t": snappedf(t, 0.05), "len": length, "night": is_night(), "bell": bell, "over": over, "p": flat,
		"cams": cams.map(func(c): return [roundi(c.pos.x), roundi(c.pos.y), c.owner, 1 if c.blind > 0 else 0]),
		"news": events.filter(func(e): return e.public).slice(-5).map(func(e): return [e.id, e.t, e.text])}
	match role:
		"ruler":
			var seen := []
			for i in people.size():
				var p: Dictionary = people[i]
				if p.seen:
					seen.append([i, roundi(p.sus), p.flags])
			s.merge({"seen": seen, "warrants": warrants, "amend": snappedf(amend_wait, 0.1), "rules": rules,
				"unrest": unrest, "seat": seat, "council": council, "left": _count("")})
		"citizen":
			for i in people.size():
				var p: Dictionary = people[i]
				if p.kind == "cit" and p.peer == peer:
					s.you = {"i": i, "pages": p.pages, "seen": p.seen, "state": p.hidden, "msg": p.msg if p.msg_t > 0 else "",
						"esc": snappedf(p.esc_t / ESCAPE_TIME, 0.05), "wall": p.wall, "wall_t": snappedf(p.wall_t, 1),
						"q": p.q if p.hidden == "taken" else {}, "q_left": snappedf(maxf(p.q_wait - p.q_t, 0), 1),
						"q_right": p.q_right, "num": p.num}
					var near := []
					for g in pages:
						if g.distance_to(p.pos) < 500:
							near.append([roundi(g.x), roundi(g.y)])
					s.pages = near
			s.post = post_district() if bell else ""
		"public":
			s.merge({"left": _count(""), "gone": _count("gone"), "taken": _count("taken"), "unrest": unrest})
		"eyes", "town":
			# watchers: the cameras' view (live), or everyone with the citizens
			# named (sent a minute late). Never the wall: citizens must go and read it.
			var seen := []
			for i in people.size():
				var p: Dictionary = people[i]
				if p.seen:
					seen.append([i, roundi(p.sus), p.flags])
			s.merge({"seen": seen, "left": _count(""), "gone": _count("gone"), "taken": _count("taken"), "unrest": unrest})
			if role == "town":
				var cits := []
				for i in people.size():
					if people[i].kind == "cit":
						cits.append([i, people[i].num])
				s.cits = cits
	return s


func _count(state: String) -> int:
	var n := 0
	for p in people:
		if p.kind == "cit" and p.hidden == state:
			n += 1
	return n


## Everything for the debrief, at the end of the round.
func summary() -> Dictionary:
	var cits := people.filter(func(p): return p.kind == "cit")
	var escaped := cits.filter(func(p): return p.stats.escaped).size()
	var taken := 0
	for p in cits:
		taken += int(p.stats.taken)
	var innocents := events.filter(func(e): return e.kind == "innocent").size()
	var free := escaped * 2 >= cits.size() and cits.size() > 0
	return {"k": "end", "free": free, "escaped": escaped, "citizens": cits.size(), "taken": taken, "innocents": innocents,
		"rules_start": Rules.wall_lines(rules_start), "rules_end": Rules.wall_lines(rules),
		"log": events.map(func(e): return [e.t, e.text, e.kind]),
		"stats": cits.map(func(p): return [p.num, p.stats.pages, p.stats.gives, p.stats.nods, p.stats.taken, p.stats.escaped, roundi(p.stats.seen)]),
		"length": length}
