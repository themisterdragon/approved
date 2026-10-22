extends Node2D
## One round: the ruler writes the rules, the day runs, the debrief follows.
## The host's screen (or a practice game) runs the town (scripts/sim.gd);
## every screen draws what its role may see (scripts/world_view.gd) from a
## snapshot, and sends back what its person does.
## Test args (after --): --autoplay (a robot plays this screen's role)
##   --seconds=N (round length)  --fast=N (run N times faster)

const SEND_EVERY := 0.1
const STEP := 1.0 / 30
const CLOSE := 2.6       # how close the camera is round a citizen

var sim: Sim             # (host and practice) the town itself
var role := "citizen"
var seat := 0
var me_peer := "me"      # (practice) the local citizen's id in the sim
var phase := "rules"     # rules -> play -> end
var snap := {}
var view: WorldView
var cam: Camera2D
var hud: CanvasLayer
var acc := 0.0
var send_t := 0.0
var rules_wait := 60.0
var autoplay := false
var fast := 1.0
var test_seconds := 0.0

# (players) smoothing between the host's snapshots
var prev_p := []
var cur_p := []
var since := 0.0
var latched := {}

# hud parts
var clock_l: Label
var phase_l: Label
var info_l: Label
var msg_l: Label
var news_box: VBoxContainer
var news_seen := {}
var wall_box: VBoxContainer
var wall_note: Label
var pages_l: Label
var eye_l: Label
var subject: PanelContainer
var subject_l: Label
var take_b: Button
var overlay: Control
var amend_buttons := {}
var buttons_box: HBoxContainer
var top_box: VBoxContainer
var hud_root: Control
var msg_card: PanelContainer
var wall_card: PanelContainer
var fold_b: Button
var pages_icons: UI.Pages
var stat_l := {}
var hint_l: Label
var hint_used := false
var wall_lines: Array = []
var hurry_on := false
var zoom_in := 1.0      # (ruler) how far in from the whole town; (citizen) the zoom itself
var look_at := Vector2.ZERO  # (ruler) the middle of the view
var dragging := false
const DELAY := 60.0
var board_history: Array = []  # (host) watchers' snapshots, for the delayed view
var board_t := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--seconds="):
			test_seconds = float(arg.substr(10))
		elif arg.begins_with("--fast="):
			fast = float(arg.substr(7))
	view = WorldView.new()
	add_child(view)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	var fx := CanvasLayer.new()
	fx.layer = 4
	add_child(fx)
	fx.add_child(UI.rain())
	fx.add_child(UI.grain())
	Net.message.connect(_net_message)
	Net.peer_left.connect(_net_left)
	match Game.mode:
		Game.Mode.PRACTICE_CITIZEN:
			role = "citizen"
			sim = Sim.new()
			var rules := {}
			var pick := Rules.ORDER.duplicate()
			pick.shuffle()
			for r in pick.slice(0, Rules.PICK):
				rules[r] = 0
			_begin(rules)
		Game.Mode.PRACTICE_RULER:
			role = "ruler"
			sim = Sim.new()
			_rules_picker()
		Game.Mode.HOST:
			sim = Sim.new()
			_assign_roles()
			if role == "ruler":
				_rules_picker()
			else:
				_waiting("The Bureau is writing the rules.")
		Game.Mode.CLIENT:
			role = Game.role
			seat = Game.seat
			_waiting("The Bureau is writing the rules." if role != "ruler" or seat != 0 else "Waiting for the town...")
			Net.send(Game.host_peer, {"k": "ready"})
	view.mode = role
	view.seat = seat
	zoom_in = CLOSE if role == "citizen" else 1.0
	if role == "public":
		view.mode = _board_mode()
		view.seat = -1
	elif role == "watch":
		view.seat = -1
	_hud()


# ------------------------------------------------------------- setting up

## What the board (and watchers) see, by the host's choice.
func _board_mode() -> String:
	var m: String = {"eyes": "eyes", "delayed": "town", "streets": "public"}.get(Game.board, "eyes")
	return m


## (host) A watcher's snapshot: live, or from a minute ago.
func _board_snap() -> Dictionary:
	var m := _board_mode()
	if m != "town":
		var s := sim.snapshot_for(m)
		s.view = m
		return s
	if board_history.is_empty() or float(sim.t) - float(board_history[0].t) < DELAY:
		var s := sim.snapshot_for("public")  # (the delayed feed hasn't started yet)
		s.view = "public"
		s.wait = DELAY - (float(sim.t) - (float(board_history[0].t) if board_history.size() > 0 else 0.0))
		return s
	return board_history[0]


## (host) Who rules this round, and tell everyone their part.
func _assign_roles() -> void:
	for p in Game.players:
		p.erase("late")
	var peers: Array = Game.players.map(func(p): return p.peer)
	Game.rulers = []
	if Game.ruler_mode == "teacher" or peers.size() < 2:
		Game.rulers = [""]
		role = "ruler"
	else:
		var n := 1 if Game.ruler_mode == "student" else mini(Game.council, peers.size() - 1)
		var pool := peers.filter(func(p): return not p in Game.last_rulers)
		if pool.size() < n:
			pool = peers.duplicate()
		pool.shuffle()
		Game.rulers = pool.slice(0, n)
		role = "public"
	for p in peers:
		var s: int = Game.rulers.find(p)
		Net.send(p, {"k": "role", "role": "ruler" if s >= 0 else "citizen", "seat": maxi(s, 0)})
	for w in Game.watchers:
		Net.send(w, {"k": "role", "role": "watch", "seat": 0})


func _begin(rules: Dictionary) -> void:
	Game.rules = rules
	var cits := []
	var council := 1
	match Game.mode:
		Game.Mode.PRACTICE_CITIZEN:
			cits = [{"peer": "me"}, {"bot": true}, {"bot": true}, {"bot": true}]
		Game.Mode.PRACTICE_RULER:
			cits = [{"bot": true}, {"bot": true}, {"bot": true}, {"bot": true}, {"bot": true}]
		Game.Mode.HOST:
			for p in Game.players:
				if not p.peer in Game.rulers and not p.get("late", false):
					cits.append({"peer": p.peer})
			council = maxi(Game.rulers.size(), 1)
	var secs := test_seconds if test_seconds > 0 else Game.minutes * 60.0
	sim.setup({"length": secs, "citizens": cits, "ruler_bot": Game.mode == Game.Mode.PRACTICE_CITIZEN,
		"council": council, "rules": rules, "questions": Game.questions()})
	if Game.mode == Game.Mode.HOST:
		Net.broadcast({"k": "start"})
	_play()


func _play() -> void:
	phase = "play"
	if overlay:
		overlay.queue_free()
		overlay = null


# ------------------------------------------------------------------ frames

func _process(delta: float) -> void:
	if sim and phase == "play":
		acc += minf(delta, 0.25) * fast
		var n := 0
		while acc >= STEP and n < 8 * int(fast):
			acc -= STEP
			sim.step(STEP)
			n += 1
		# the delayed feed: keep a minute of what watchers would see
		board_t -= delta
		if board_t <= 0 and Game.board == "delayed" and Game.mode == Game.Mode.HOST:
			board_t = SEND_EVERY
			var hs := sim.snapshot_for("town")
			hs.view = "town"
			board_history.append(hs)
			while board_history.size() > 1 and float(sim.t) - float(board_history[1].t) >= DELAY:
				board_history.pop_front()
		if role == "public":
			var bs := _board_snap()
			view.mode = bs.view
			_show(bs)
		else:
			_show(sim.snapshot_for(role, me_peer, seat))
		send_t -= delta
		if send_t <= 0 and Game.mode == Game.Mode.HOST:
			send_t = SEND_EVERY
			for p in Game.players:
				if p.get("late", false):
					continue
				var s: int = Game.rulers.find(p.peer)
				Net.send(p.peer, sim.snapshot_for("ruler" if s >= 0 else "citizen", p.peer, maxi(s, 0)))
			var lookers: Array = Game.watchers + Game.players.filter(func(p): return p.get("late", false)).map(func(p): return p.peer)
			if lookers.size() > 0:
				var ws := _board_snap()
				for w in lookers:
					Net.send(w, ws)
		if sim.over:
			_end(sim.summary())
	elif Game.mode == Game.Mode.CLIENT and phase == "play" and not cur_p.is_empty():
		since += delta
		var k := clampf(since / SEND_EVERY, 0, 1)
		var pos := PackedVector2Array()
		pos.resize(cur_p.size() / 4)
		for i in pos.size():
			var a := Vector2(prev_p[i * 4], prev_p[i * 4 + 1]) if prev_p.size() == cur_p.size() else Vector2(cur_p[i * 4], cur_p[i * 4 + 1])
			pos[i] = a.lerp(Vector2(cur_p[i * 4], cur_p[i * 4 + 1]), k)
		view.pos = pos
	if phase == "rules" and sim and role != "ruler":
		rules_wait -= delta
		if rules_wait <= 0:
			_begin(Rules.DEFAULT.duplicate())
	hud_root.visible = phase == "play"
	if phase == "play":
		_input_frame(delta)
		_camera(delta)
		_update_hud()


func _show(s: Dictionary) -> void:
	snap = s
	var flat: Array = s.p
	var n := flat.size() / 4
	if Game.mode != Game.Mode.CLIENT:
		var pos := PackedVector2Array()
		pos.resize(n)
		for i in n:
			pos[i] = Vector2(flat[i * 4], flat[i * 4 + 1])
		view.pos = pos
	view.looks.resize(n)
	view.bits.resize(n)
	for i in n:
		view.looks[i] = int(flat[i * 4 + 2])
		view.bits[i] = int(flat[i * 4 + 3])
	view.cams = s.cams
	view.night = move_toward(view.night, 1.0 if s.night else 0.0, 0.02)
	view.seen = {}
	for e in s.get("seen", []):
		view.seen[int(e[0])] = [int(e[1]), int(e[2])]
	view.pages = s.get("pages", [])
	view.cits = {}
	for c in s.get("cits", []):
		view.cits[int(c[0])] = int(c[1])
	view.me = int(s.you.i) if s.has("you") else -1


func _camera(delta: float) -> void:
	var vp := get_viewport_rect().size
	var world := view.world_size()
	var fit := minf(vp.x / world.x, vp.y / world.y)
	if role == "citizen" and view.me >= 0 and view.me < view.pos.size() and snap.get("you", {}).get("state", "") == "":
		# close in round yourself (the mouse wheel steps in or out a little)
		var target := view.pos[view.me] + Vector2(0, -10)
		cam.zoom = cam.zoom.lerp(Vector2.ONE * zoom_in, 1 - exp(-delta * 8))
		cam.position = cam.position.lerp(target, 1 - exp(-delta * 6)) if cam.position != Vector2.ZERO else target
	elif role == "ruler":
		# the whole town, or closer with the wheel; arrow keys, WASD or a
		# right-button drag move round it
		var z := fit * zoom_in
		cam.zoom = cam.zoom.lerp(Vector2.ONE * z, 1 - exp(-delta * 10))
		var mv := Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		look_at += mv * 700.0 * delta / cam.zoom.x
		if look_at == Vector2.ZERO:
			look_at = world / 2
		cam.position = look_at
	else:
		cam.zoom = Vector2.ONE * fit
		cam.position = world / 2
	# never past the town's edge (and centred when the town is smaller than the screen)
	var half := vp / cam.zoom / 2
	for k in 2:
		cam.position[k] = world[k] / 2 if half[k] * 2 >= world[k] else clampf(cam.position[k], half[k], world[k] - half[k])
	if role == "ruler":
		look_at = cam.position


# ------------------------------------------------------------------- input

func _input_frame(_delta: float) -> void:
	if role != "citizen":
		if autoplay and role == "ruler":
			_auto_ruler()
		return
	var you: Dictionary = snap.get("you", {})
	if you.is_empty():
		return
	var inp := {}
	if you.state == "":
		var mv := Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if autoplay:
			mv = Vector2(sin(Time.get_ticks_msec() / 1300.0), cos(Time.get_ticks_msec() / 1700.0))
		inp.mv = [mv.x, mv.y]
		inp.hurry = hurry_on or Input.is_physical_key_pressed(KEY_SHIFT)
	for k in latched:
		inp[k] = latched[k]
	latched = {}
	if Game.mode == Game.Mode.CLIENT:
		send_t -= get_process_delta_time()
		if send_t <= 0 or inp.has("to") or inp.has("ans") or inp.has("nod") or inp.has("give"):
			send_t = 0.05
			Net.send(Game.host_peer, {"k": "in", "i": inp})
	elif sim:
		sim.input(me_peer, inp)


func _unhandled_input(event: InputEvent) -> void:
	if phase != "play":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE, KEY_E:
				latched.nod = true
			KEY_F, KEY_Q:
				latched.give = true
			KEY_1, KEY_2, KEY_3, KEY_4:
				latched.ans = event.physical_keycode - KEY_1
			KEY_TAB:
				if wall_box:
					_fold_wall()
			KEY_ENTER, KEY_KP_ENTER:
				if role == "ruler":
					_take()
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var k := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.15
		if role == "citizen":
			zoom_in = clampf(zoom_in * k, 1.8, 3.6)
		elif role == "ruler":
			var before := get_global_mouse_position()
			zoom_in = clampf(zoom_in * k, 1.0, 3.0)
			look_at += (before - look_at) * (1 - 1 / k)  # (zoom towards the mouse)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and role == "ruler":
		dragging = event.pressed
		return
	if event is InputEventMouseMotion and dragging:
		look_at -= event.relative / cam.zoom
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at := get_global_mouse_position()
		if role == "citizen":
			latched.to = [at.x, at.y]  # walk there
		elif role == "ruler":
			_ruler_click(at)


func _ruler_click(at: Vector2) -> void:
	var c := view.cam_at(at)
	if c >= 0 and int(view.cams[c][2]) == seat:
		view.picked_cam = c
		view.picked = -1
		return
	if view.picked_cam >= 0:
		_cmd({"c": "cam", "i": view.picked_cam, "x": at.x, "y": at.y})
		view.picked_cam = -1
		return
	view.picked = view.person_at(at)


func _take() -> void:
	if view.picked >= 0:
		_cmd({"c": "take", "i": view.picked})
		view.picked = -1


func _cmd(c: Dictionary) -> void:
	if sim:
		_run_cmd(c, seat, "The Bureau" if Game.rulers.size() <= 1 else "Council member %s" % "ABC"[seat])
	else:
		Net.send(Game.host_peer, {"k": "cmd", "cmd": c})


## (host) A ruler's command, from this screen or a council member's.
func _run_cmd(c: Dictionary, from_seat: int, who: String) -> void:
	match c.get("c"):
		"cam":
			sim.move_camera(int(c.i), Vector2(float(c.x), float(c.y)), from_seat)
		"take":
			sim.detain(int(c.i), who)
		"amend":
			sim.amend(String(c.rule), int(c.v), who)


func _auto_ruler() -> void:
	if Engine.get_process_frames() % 90 == 0:
		for i in view.seen:
			if view.seen[i][0] > 60:
				_cmd({"c": "take", "i": i})
				return
		var mine := []
		for i in view.cams.size():
			if int(view.cams[i][2]) == seat:
				mine.append(i)
		if mine.size() > 0:
			var i: int = mine[randi() % mine.size()]
			var p := Town.get_town().random_walkable(RandomNumberGenerator.new())
			_cmd({"c": "cam", "i": i, "x": p.x, "y": p.y})


# --------------------------------------------------------------- network

func _net_message(peer: String, d: Dictionary) -> void:
	if Game.mode == Game.Mode.HOST:
		match d.get("k"):
			"hello":  # joined after the day began: watch this one, play the next
				if not peer in Game.watchers and Game.players.all(func(p): return p.peer != peer):
					if d.get("watch", false):
						Game.watchers.append(peer)
					else:
						Game.players.append({"peer": peer, "late": true})
					Net.send(peer, {"k": "role", "role": "watch", "seat": 0})
			"ready":
				if Game.rulers.size() > 0 and peer == Game.rulers[0] and phase == "rules":
					Net.send(peer, {"k": "pick"})
			"rules":
				if phase == "rules" and Game.rulers.size() > 0 and peer == Game.rulers[0]:
					_begin(_clean_rules(d.get("rules", {})))
			"in":
				if sim and phase == "play" and d.get("i") is Dictionary:
					sim.input(peer, d.i)
			"cmd":
				var s: int = Game.rulers.find(peer)
				if sim and phase == "play" and s >= 0 and d.get("cmd") is Dictionary:
					_run_cmd(d.cmd, s, "The Bureau" if Game.rulers.size() <= 1 else "Council member %s" % "ABC"[s])
	else:
		match d.get("k"):
			"pick":
				_rules_picker()
			"start":
				_play()
			"s":
				if phase != "play":
					_play()
				if role == "watch":
					view.mode = String(d.get("view", "eyes"))
				prev_p = cur_p
				cur_p = d.p
				since = 0.0
				_show(d)
			"end":
				_end(d)
			"role":
				Game.role = d.role
				Game.seat = int(d.get("seat", 0))
				get_tree().reload_current_scene()
			"menu":
				Net.close()
				get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _net_left(peer: String) -> void:
	if Game.mode == Game.Mode.HOST:
		Game.players = Game.players.filter(func(p): return p.peer != peer)
		Game.watchers.erase(peer)
		if sim:
			sim.leave(peer)
	elif peer == Game.host_peer:
		Net.close()
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _clean_rules(r) -> Dictionary:
	var out := {}
	if r is Dictionary:
		for k in r:
			if Rules.CARDS.has(k) and out.size() < Rules.PICK:
				out[k] = clampi(int(r[k]), 0, Rules.CARDS[k].texts.size() - 1)
	return out if out.size() > 0 else Rules.DEFAULT.duplicate()


# ------------------------------------------------------------------ the end

func _end(summary: Dictionary) -> void:
	if phase == "end":
		return
	phase = "end"
	Game.summary = summary
	if Game.mode == Game.Mode.HOST:
		Net.broadcast(summary)
		Game.last_rulers = Game.rulers.duplicate()
	if overlay:
		overlay.queue_free()
	for c in hud.get_children():  # (the day's HUD goes; the record takes the screen)
		c.visible = false
	overlay = Debrief.new(summary, Game.mode != Game.Mode.CLIENT, _again, _to_menu)
	hud.add_child(overlay)


func _again() -> void:
	get_tree().reload_current_scene()


func _to_menu() -> void:
	if Game.mode == Game.Mode.HOST:
		Net.broadcast({"k": "menu"})
	Net.close()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


# --------------------------------------------------------------------- hud

func _hud() -> void:
	# everything of the day's HUD sits under the overlays (rules, questioning, debrief)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_root)
	hud.move_child(hud_root, 0)
	# top left: the clock, the time of day, and who you are
	var tl := UI.card(hud_root)
	tl.position = Vector2(20, 18)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tl.add_child(tv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	tv.add_child(row)
	clock_l = UI.label("", UI.head, 50, UI.PAPER, row)
	phase_l = UI.label("", UI.head, 26, UI.MUTED, row)
	phase_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_l = UI.label("", UI.bold, 22, UI.MUTED, tv)
	top_box = tv
	# bottom left: the last thing that happened in town (two lines at most)
	news_box = VBoxContainer.new()
	news_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 22)
	news_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	news_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	news_box.add_theme_constant_override("separation", 4)
	hud_root.add_child(news_box)
	# bottom middle: what's happening to you, on a strip of its own
	msg_card = UI.card(hud_root, 0.88)
	msg_l = UI.label("", UI.bold, 26, UI.PAPER, msg_card)
	msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 120)
	msg_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	msg_card.visible = false
	match role:
		"citizen":
			_citizen_hud()
		"ruler":
			_ruler_hud()


## The wall, top right: a card you can fold away (Tab) to see the streets.
func _wall_panel(title: String) -> void:
	var p := UI.card(hud_root)
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.position.y = 18
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	wall_card = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.label(title, UI.head, 32, UI.PAPER, head)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fold := UI.button("HIDE  (TAB)", _fold_wall, head, Vector2(130, 36), 17)
	fold.focus_mode = Control.FOCUS_NONE
	fold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fold_b = fold
	wall_box = VBoxContainer.new()
	wall_box.add_theme_constant_override("separation", 10)
	v.add_child(wall_box)
	wall_note = UI.label("", UI.body, 19, UI.MUTED, v)
	wall_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wall_note.custom_minimum_size.x = 430


func _fold_wall() -> void:
	wall_box.visible = not wall_box.visible
	wall_note.visible = wall_box.visible
	fold_b.text = "HIDE  (TAB)" if wall_box.visible else "SHOW  (TAB)"


func _citizen_hud() -> void:
	_wall_panel("THE WALL")
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 14)
	top_box.add_child(pr)
	pages_icons = UI.Pages.new()
	pr.add_child(pages_icons)
	pages_l = UI.label("", UI.bold, 22, UI.PAPER, pr)
	pages_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eye_l = UI.label("", UI.head, 34, UI.RED_BRIGHT, top_box)
	buttons_box = HBoxContainer.new()
	buttons_box.add_theme_constant_override("separation", 12)
	hud_root.add_child(buttons_box)
	buttons_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 22)
	buttons_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var hb := UI.action("HURRY", "Shift", func(): hurry_on = not hurry_on, buttons_box, 170)
	hb.toggle_mode = true
	UI.action("NOD", "Space", func(): latched.nod = true, buttons_box, 150)
	UI.action("PASS A PAGE", "F", func(): latched.give = true, buttons_box, 210)


func _ruler_hud() -> void:
	_wall_panel("THE WALL")
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 22)
	top_box.add_child(stats)
	for k in ["WARRANTS", "UNREST", "AT LARGE"]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -6)
		stats.add_child(v)
		var n := UI.label("0", UI.head, 34, UI.PAPER, v)
		UI.label(k, UI.bold, 15, UI.MUTED, v)
		stat_l[k] = n
	info_l.visible = false
	subject = UI.card(hud_root, 0.9)
	subject.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 22)
	subject.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	subject.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subject.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := VBoxContainer.new()
	sb.add_theme_constant_override("separation", 10)
	subject.add_child(sb)
	UI.label("UNDER WATCH", UI.head, 28, UI.PAPER, sb)
	subject_l = UI.label("", UI.bold, 22, UI.PAPER, sb)
	subject_l.custom_minimum_size.x = 380
	subject_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	take_b = UI.button("TAKE FOR QUESTIONING", _take, sb, Vector2(380, 62), 26)
	take_b.focus_mode = Control.FOCUS_NONE
	UI.label("or press Enter", UI.body, 17, UI.MUTED, sb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# a hint along the bottom, until they've got the hang of it
	hint_l = UI.label("Click one of your cameras, then a street, to move it.   Click someone on camera to watch them.   Wheel: zoom.", UI.body, 20, UI.PAPER, hud_root)
	hint_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 26)
	hint_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_l.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _update_hud() -> void:
	if snap.is_empty():
		return
	var left := maxf(float(snap.len) - float(snap.t), 0)
	clock_l.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
	phase_l.text = ("NIGHT · CURFEW" if snap.night and Game.rules.has("curfew") else ("NIGHT" if snap.night else "DAY")) + ("  ·  THE BELL" if snap.bell else "")
	phase_l.add_theme_color_override("font_color", UI.RED_BRIGHT if snap.bell else UI.MUTED)
	_news()
	match role:
		"citizen":
			_citizen_frame()
		"ruler":
			_ruler_frame()
		"public", "watch":
			var feed: String = {"eyes": "The Bureau's cameras, live", "town": "The whole town, one minute ago", "public": "The streets"}.get(view.mode, "")
			if snap.has("wait"):
				feed = "The whole town: the feed begins in %d s" % int(snap.wait)
			info_l.text = "%s\nMissing from the count: %d     Taken: %d" % [feed, int(snap.get("gone", 0)), int(snap.get("taken", 0))]
	msg_card.visible = msg_l.text != ""


func _news() -> void:
	for e in snap.get("news", []):
		if news_seen.has(int(e[0])):
			continue
		news_seen[int(e[0])] = true
		var l := UI.label("%d:%02d   %s" % [int(e[1]) / 60, int(e[1]) % 60, e[2]], UI.body, 20, UI.PAPER, news_box)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 620
		l.set_meta("t", Time.get_ticks_msec())
		while news_box.get_child_count() > 2:
			news_box.get_child(0).free()
	# each line fades after a while, so the corner is empty when nothing's happening
	for l in news_box.get_children():
		var age := (Time.get_ticks_msec() - int(l.get_meta("t"))) / 1000.0
		l.modulate.a = clampf(1.0 - (age - 9.0) / 2.0, 0.0, 1.0)


func _citizen_frame() -> void:
	var you: Dictionary = snap.get("you", {})
	if you.is_empty():
		return
	info_l.text = "You are Citizen %d" % int(you.num)
	pages_icons.set_count(int(you.pages), Sim.PAGES_NEEDED)
	pages_l.text = "torn pages"
	eye_l.text = "YOU ARE BEING WATCHED" if you.seen else ""
	eye_l.visible = you.seen
	if wall_lines != you.wall:
		wall_lines = (you.wall as Array).duplicate()
		for c in wall_box.get_children():
			c.free()
		for r in you.wall:
			var l := UI.label("• " + r, UI.bold, 21, UI.PAPER, wall_box)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 430
	var ago := float(snap.t) - float(you.wall_t)
	wall_note.text = "As you read it just now." if ago < 3 else "As you read it %d:%02d ago. It may have changed." % [int(ago) / 60, int(ago) % 60]
	var m: String = you.msg
	if snap.get("post", "") != "":
		m = "THE BELL: stand in %s." % Town.get_town().names[snap.post] + ("\n" + m if m != "" else "")
	if float(you.esc) > 0:
		m = "Slipping out... keep out of sight. %d%%" % int(float(you.esc) * 100)
	msg_l.text = m
	match String(you.state):
		"taken":
			_questioning(you)
		"gone":
			_outside()
		_:
			if overlay and phase == "play":
				overlay.queue_free()
				overlay = null


func _ruler_frame() -> void:
	stat_l.WARRANTS.text = str(int(snap.warrants))
	stat_l.UNREST.text = str(int(snap.unrest))
	stat_l["AT LARGE"].text = str(int(snap.left))
	stat_l.WARRANTS.add_theme_color_override("font_color", UI.RED_BRIGHT if int(snap.warrants) == 0 else UI.PAPER)
	# the wall, with each rule amendable
	if amend_buttons.is_empty():
		for r in Rules.ORDER:
			if not (snap.rules as Dictionary).has(r):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			wall_box.add_child(row)
			var l := UI.label("", UI.bold, 21, UI.PAPER, row)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 300
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b := UI.button("AMEND", func(): _amend(r), row, Vector2(116, 44), 20)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.focus_mode = Control.FOCUS_NONE
			amend_buttons[r] = [l, b]
	for r in amend_buttons:
		amend_buttons[r][0].text = Rules.text(r, int(snap.rules[r]))
		amend_buttons[r][1].disabled = float(snap.amend) > 0
	wall_note.text = "You may amend again in %d s." % int(snap.amend) if float(snap.amend) > 0 else "The townsfolk obey an amendment at once. Citizens only know what they last read."
	var p := view.picked
	if p >= 0 and view.seen.has(p):
		var sus: int = view.seen[p][0]
		var why := []
		for b in Sim.FLAG_NAMES:
			if view.seen[p][1] & b:
				why.append(Sim.FLAG_NAMES[b])
		subject_l.text = "Suspicion: %d%%\n%s" % [sus, ("Seen " + ", ".join(why) + ".") if why.size() > 0 else "Nothing out of place."]
		take_b.disabled = int(snap.warrants) <= 0
		subject.visible = true
		hint_used = true
	else:
		view.picked = -1
		subject.visible = false
	if view.picked_cam >= 0:
		hint_used = true
	hint_l.visible = not hint_used and float(snap.t) < 90.0


func _amend(rule: String) -> void:
	var v: int = (int(snap.rules[rule]) + 1) % Rules.CARDS[rule].texts.size()
	_cmd({"c": "amend", "rule": rule, "v": v})


# --------------------------------------------------------------- overlays

func _waiting(text: String) -> void:
	phase = "rules"
	if overlay:  # (a student ruler's rules picker must go, or it covers their whole day)
		overlay.queue_free()
	overlay = ColorRect.new()
	overlay.color = Color(UI.INK, 0.92)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(box)
	box.add_child(UI.Stamp.new("PENDING", 80, -0.08))
	var l := UI.label(text, UI.bold, 34, UI.PAPER, box)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if role == "watch":
		var how := UI.label("You're watching. You'll see the town as the host chose: the Bureau's cameras, or everyone a minute behind.", UI.body, 26, UI.MUTED, box)
		how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if role == "citizen":
		var how := UI.label("You are a citizen. Blend in with the crowd, find three torn pages, and slip out through the gate or the old culvert.\nKeep the rules, as far as you know them. The wall in Assembly Square says what they are now.", UI.body, 26, UI.MUTED, box)
		how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size.x = 1100
		how.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


## The ruler posts the rules: three cards, each in the wording they choose.
func _rules_picker() -> void:
	phase = "rules"
	if overlay:
		overlay.queue_free()
	overlay = ColorRect.new()
	overlay.color = Color(UI.INK, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	overlay.add_child(box)
	var h := UI.label("POST THE RULES", UI.head, 64, UI.PAPER, box)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := UI.label("Choose %d. Click a chosen rule again to change its wording. The wall will read exactly this." % Rules.PICK, UI.body, 26, UI.MUTED, box)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chosen := Rules.DEFAULT.duplicate()
	var rows := {}
	var go_box := {}  # (a lambda captures locals as they are when it's made, so the button goes in here)
	var refresh := func() -> void:
		for r in rows:
			var on := chosen.has(r)
			rows[r].text = ("■  " if on else "□  ") + Rules.CARDS[r].title.to_upper() + ":  " + Rules.text(r, int(chosen.get(r, 0)))
		if go_box.has("b"):
			go_box.b.disabled = chosen.size() != Rules.PICK
	for r in Rules.ORDER:
		var b := UI.button("", func():
			if chosen.has(r):
				var nv: int = int(chosen[r]) + 1
				if nv >= Rules.CARDS[r].texts.size():
					chosen.erase(r)
				else:
					chosen[r] = nv
			elif chosen.size() < Rules.PICK:
				chosen[r] = 0
			refresh.call(), box, Vector2(1300, 64), 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rows[r] = b
	var go := UI.button("POST THEM", func():
		if Game.mode == Game.Mode.CLIENT:
			Net.send(Game.host_peer, {"k": "rules", "rules": chosen})
			_waiting("The rules are posted. The day begins...")
		else:
			_begin(chosen), box, Vector2(420, 72), 34)
	go_box.b = go
	refresh.call()
	if autoplay:
		go.pressed.emit.call_deferred()
	await get_tree().process_frame
	if is_instance_valid(go):
		go.grab_focus()


func _questioning(you: Dictionary) -> void:
	if overlay == null or not overlay.has_meta("q"):
		if overlay:
			overlay.queue_free()
		overlay = ColorRect.new()
		overlay.color = Color(0.05, 0.02, 0.03, 0.96)
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.set_meta("q", "")
		hud.add_child(overlay)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 14)
		overlay.add_child(box)
		var h := UI.label("YOU HAVE BEEN TAKEN FOR QUESTIONING", UI.head, 52, UI.RED_BRIGHT, box)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var q := UI.label("", UI.bold, 36, UI.PAPER, box)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		q.custom_minimum_size.x = 1300
		q.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		overlay.set_meta("ql", q)
		var bs := []
		for i in 4:
			var b := UI.button("", func(): latched.ans = i, box, Vector2(900, 64), 28)
			bs.append(b)
		overlay.set_meta("bs", bs)
		var note := UI.label("", UI.body, 24, UI.MUTED, box)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay.set_meta("note", note)
	var qd: Dictionary = you.q
	if qd.is_empty():
		return
	if overlay.get_meta("q") != qd.q:
		overlay.set_meta("q", qd.q)
		overlay.get_meta("ql").text = "\"%s\"" % qd.q
		var bs: Array = overlay.get_meta("bs")
		for i in 4:
			bs[i].text = "%d.  %s" % [i + 1, qd.answers[i]]
		if autoplay:
			latched.ans = randi() % 4
	overlay.get_meta("note").text = "Your pages were taken. Answer two correctly to be released.  Correct: %d of 2.  %s" % [int(you.q_right),
		("At least %d s more." % int(you.q_left)) if float(you.q_left) > 0 else ""] + ("\n" + String(you.msg) if you.msg != "" else "")


func _outside() -> void:
	if overlay and overlay.has_meta("out"):
		return
	if overlay:
		overlay.queue_free()
	overlay = ColorRect.new()
	overlay.color = Color(UI.INK, 0.9)
	overlay.set_meta("out", true)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(box)
	var l := UI.label("YOU ARE OUTSIDE THE WALLS", UI.head, 64, UI.PAPER, box)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := UI.label("The rain is the same out here. Nobody is counting you any more.\nWait for the day to end; then tell the others what it took.", UI.body, 28, UI.MUTED, box)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
