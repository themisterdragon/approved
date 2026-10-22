extends Control
## Title, hosting a class game (who rules, how long, which questions),
## the lobby with the class code, joining, practice, and how to play.
## Behind it all the town goes about its evening.
## Test args (after --): --practice=citizen|ruler  --test-host=N (host on
## this computer, start when N have joined; --ruler=teacher|student|council)
## --test-join (join the host on this computer)  --test-watch (join to watch)
## --board=eyes|delayed|streets

const SLOGANS := ["ORDER IS KINDNESS", "A QUIET STREET IS A HAPPY STREET", "YOUR NEIGHBOUR IS LISTENING. SO ARE WE.",
	"WALK. HASTE SUGGESTS GUILT.", "THE WALL REMEMBERS SO YOU DON'T HAVE TO"]

var page: VBoxContainer
var bg_sim := Sim.new()
var view: WorldView
var cam: Camera2D
var slogan: Label
var lobby_l: Label
var status_l: Label
var code_edit: LineEdit
var hello_sent := false
var test_host := 0


func _ready() -> void:
	# the town at dusk, nobody in particular in it
	var world := Node2D.new()
	add_child(world)
	bg_sim.setup({"length": 99999, "citizens": [], "ruler_bot": false, "rules": {"walk": 0}})
	bg_sim.t = 0
	bg_sim.cams = []
	view = WorldView.new()
	view.mode = "menu"
	view.night = 0.8
	world.add_child(view)
	cam = Camera2D.new()
	cam.zoom = Vector2(1.6, 1.6)
	world.add_child(cam)
	cam.make_current()
	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(UI.rain())
	var dim := ColorRect.new()
	dim.color = Color(UI.INK, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dim)
	ui.add_child(UI.grain())
	page = VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 16)
	ui.add_child(page)
	slogan = UI.label("", UI.head, 30, Color(UI.PAPER, 0.5))
	ui.add_child(slogan)
	slogan.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	slogan.grow_horizontal = Control.GROW_DIRECTION_BOTH
	slogan.grow_vertical = Control.GROW_DIRECTION_BEGIN
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Net.opened.connect(_net_opened)
	Net.peer_joined.connect(_peer_joined)
	Net.peer_left.connect(_peer_left)
	Net.message.connect(_net_message)
	Net.failed.connect(_net_failed)
	if Game.mode == Game.Mode.HOST and Net.active:
		_lobby()
	else:
		_title()
	for arg in OS.get_cmdline_user_args():
		if arg == "--practice=citizen":
			_practice.call_deferred(Game.Mode.PRACTICE_CITIZEN)
		elif arg == "--practice=ruler":
			_practice.call_deferred(Game.Mode.PRACTICE_RULER)
		elif arg.begins_with("--ruler="):
			Game.ruler_mode = arg.substr(8)
			Game.council = 2
		elif arg.begins_with("--test-host="):
			test_host = int(arg.substr(12))
	if test_host > 0:
		_open_town()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--board="):
			Game.board = arg.substr(8)
	if "--test-join" in OS.get_cmdline_user_args() or "--test-watch" in OS.get_cmdline_user_args():
		Game.watching = "--test-watch" in OS.get_cmdline_user_args()
		Game.mode = Game.Mode.CLIENT
		Game.code = ""
		Net.join("")
		_waiting("Connecting...")


func _process(delta: float) -> void:
	bg_sim.step(minf(delta, 0.1))
	var s := bg_sim.snapshot_for("public")
	var flat: Array = s.p
	var n := flat.size() / 4
	view.pos.resize(n)
	view.looks.resize(n)
	view.bits.resize(n)
	for i in n:
		view.pos[i] = Vector2(flat[i * 4], flat[i * 4 + 1])
		view.looks[i] = int(flat[i * 4 + 2])
		view.bits[i] = int(flat[i * 4 + 3])
	var tm := Time.get_ticks_msec() / 1000.0
	cam.position = Vector2(960 + 420 * sin(tm * 0.03), 540 + 200 * sin(tm * 0.047))
	slogan.text = SLOGANS[int(tm / 7.0) % SLOGANS.size()]


func _clear() -> void:
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()


func _text(t: String, font: Font, size: int, color := UI.PAPER) -> Label:
	var l := UI.label(t, font, size, color, page)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1200
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return l


func _focus_first() -> void:
	await get_tree().process_frame
	for b in page.find_children("*", "Button", true, false):
		b.grab_focus()
		return


# ------------------------------------------------------------------- pages

func _title() -> void:
	_clear()
	Game.mode = Game.Mode.PRACTICE_CITIZEN
	page.add_child(UI.Stamp.new("APPROVED", 124, -0.08))
	_text("A game about rules, watching, and getting out.", UI.body, 30, UI.MUTED)
	UI.button("HOST A CLASS GAME", _host_setup, page)
	UI.button("JOIN A CLASS GAME", _join_page, page)
	UI.button("PRACTICE AS A CITIZEN", func(): _practice(Game.Mode.PRACTICE_CITIZEN), page)
	UI.button("PRACTICE AS THE BUREAU", func(): _practice(Game.Mode.PRACTICE_RULER), page)
	UI.button("HOW TO PLAY", _how, page)
	var build := FileAccess.get_file_as_string("res://data/build.txt").strip_edges()
	if build != "":
		_text("build " + build, UI.body, 18, Color(UI.MUTED, 0.6))
	_focus_first()


func _how() -> void:
	_clear()
	_text("HOW TO PLAY", UI.head, 60)
	_text("One player is the Bureau. Everyone else is a citizen, hidden in a crowd that looks just like them.", UI.body, 26)
	page.add_child(Crowd.new())
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 24)
	page.add_child(cols)
	for side in [["CITIZENS", [
			"Find three torn pages.",
			"Slip out by the south gate or the old culvert in the west.",
			"Walk like everyone else, and keep the rules as you last read them on the wall in Assembly Square.",
			"Nod to find each other. Pass a page to someone you trust.",
			"Taken for questioning? Answer two questions on your reading."]],
		["THE BUREAU", [
			"Post three rules, worded your way.",
			"Watch through your cameras. Click one, then a street, to move it.",
			"Anyone breaking a rule on camera is circled.",
			"Warrants are few, and taking the innocent goes on the record.",
			"Amend a rule: the townsfolk obey at once. Citizens don't know until they read the wall."]]]:
		var c := UI.card(cols, 0.88)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		c.add_child(v)
		UI.label(side[0], UI.head, 34, UI.PAPER, v)
		for line in side[1]:
			var l := UI.label("•  " + line, UI.body, 22, UI.PAPER, v)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 520
	_text("Walk: WASD, arrows or click   ·   Hurry: Shift   ·   Nod: Space   ·   Pass a page: F   ·   Answer: 1-4", UI.bold, 21, UI.MUTED)
	UI.button("BACK", _title, page)
	_focus_first()


## The twelve kinds of townsfolk in a row, walking on the spot.
class Crowd extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(12 * 64, 92)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var tm := Time.get_ticks_msec() / 1000.0
		for i in Figures.LOOKS.size():
			var feet := Vector2(32 + i * 64, 84)
			Figures.ellipse(self, feet, 16, 5, Color(0, 0, 0, 0.4))
			Figures.draw(self, feet, i, Figures.DOWN, tm * 5.0 + i, true, false, false, 2.1)


func _practice(m: int) -> void:
	Game.mode = m
	Game.rulers = [""]
	get_tree().change_scene_to_file("res://scenes/round.tscn")


func _choice_row(label: String, options: Array, get_v: Callable, set_v: Callable) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var l := UI.label(label, UI.bold, 26, UI.PAPER, row)
	l.custom_minimum_size.x = 260
	var buttons := []
	var refresh := func() -> void:
		for i in options.size():
			buttons[i].text = ("■ " if get_v.call() == options[i][1] else "□ ") + options[i][0]
	for o in options:
		var b := UI.button("", func():
			set_v.call(o[1])
			refresh.call(), row, Vector2(250, 56), 22)
		buttons.append(b)
	refresh.call()


func _host_setup() -> void:
	_clear()
	_text("HOST A CLASS GAME", UI.head, 64)
	_text("Your screen runs the town. Show it on the board: it shows the clock, the news and empty streets, never the people. If you rule, keep your screen to yourself.", UI.body, 24, UI.MUTED)
	_choice_row("Who rules", [["The teacher", "teacher"], ["One student", "student"], ["Council of 2", "c2"], ["Council of 3", "c3"]],
		func(): return Game.ruler_mode if Game.ruler_mode != "council" else "c%d" % Game.council,
		func(v):
			if v.begins_with("c"):
				Game.ruler_mode = "council"
				Game.council = int(v.substr(1))
			else:
				Game.ruler_mode = v)
	_choice_row("The board shows", [["Cameras (live)", "eyes"], ["Town (1 min late)", "delayed"], ["Empty streets", "streets"]],
		func(): return Game.board, func(v): Game.board = v)
	_choice_row("Length of a day", [["5 minutes", 5], ["7 minutes", 7], ["9 minutes", 9]],
		func(): return Game.minutes, func(v): Game.minutes = v)
	var sets := Game.question_sets()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var l := UI.label("Questions on", UI.bold, 26, UI.PAPER, row)
	l.custom_minimum_size.x = 260
	for s in sets:
		var b := UI.button("", func(): pass, row, Vector2(250, 56), 22)
		var show := func(): b.text = ("■ " if s in Game.sets else "□ ") + s
		b.pressed.connect(func():
			if s in Game.sets:
				if Game.sets.size() > 1:
					Game.sets.erase(s)
			else:
				Game.sets.append(s)
			show.call())
		show.call()
	_text("The board (and anyone just watching): cameras live teaches the ruler nothing new; the town a minute late labels the citizens, so a ruler could glean where people were. It never shows the wall's current wording.", UI.body, 21, UI.MUTED)
	_text("A 45-minute period fits a practice day and a second day for review, each with time to talk after.", UI.body, 22, UI.MUTED)
	UI.button("OPEN THE TOWN", _open_town, page)
	UI.button("BACK", _title, page)
	_focus_first()


func _open_town() -> void:
	Game.mode = Game.Mode.HOST
	Game.code = Net.new_code()
	Game.players = []
	Game.watchers = []
	Net.host(Game.code)
	_lobby()
	status_l.text = "Opening the town..."


func _lobby() -> void:
	_clear()
	_text("CLASS CODE", UI.bold, 34, UI.MUTED)
	_text(" ".join(Game.code.split("")) if Net.web() else "This computer (players join on the same network)", UI.head, 120 if Net.web() else 40)
	_text("Students: open this page, choose JOIN A CLASS GAME and type the code.", UI.body, 26, UI.MUTED)
	lobby_l = _text("", UI.bold, 34)
	status_l = _text("", UI.body, 24, UI.MUTED)
	UI.button("START THE DAY", _start, page)
	UI.button("CLOSE THE TOWN", func():
		Net.close()
		_title(), page)
	_refresh()
	_focus_first()


func _refresh() -> void:
	if lobby_l and is_instance_valid(lobby_l):
		var need := 1 if Game.ruler_mode == "teacher" else (2 if Game.ruler_mode == "student" else Game.council + 1)
		lobby_l.text = "%d joined to play, %d to watch.%s" % [Game.players.size(), Game.watchers.size(), "" if Game.players.size() >= need else "  (At least %d needed.)" % need]


func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/round.tscn")


func _join_page() -> void:
	_clear()
	Game.mode = Game.Mode.CLIENT
	_text("JOIN A CLASS GAME", UI.head, 64)
	code_edit = LineEdit.new()
	code_edit.max_length = 5 if Net.web() else 40
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.add_theme_font_override("font", UI.head)
	code_edit.add_theme_font_size_override("font_size", 80)
	code_edit.custom_minimum_size = Vector2(520, 120)
	code_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	code_edit.placeholder_text = "CODE" if Net.web() else "host address"
	code_edit.text_submitted.connect(func(_t): _join_go())
	page.add_child(code_edit)
	if not Net.web():
		_text("On a computer: type the host's network address, or leave it empty for this computer.", UI.body, 22, UI.MUTED)
	UI.button("JOIN AND PLAY", func():
		Game.watching = false
		_join_go(), page)
	UI.button("JUST WATCH", func():
		Game.watching = true
		_join_go(), page)
	UI.button("BACK", _title, page)
	status_l = _text("", UI.body, 24, UI.MUTED)
	await get_tree().process_frame
	code_edit.grab_focus()


func _join_go() -> void:
	var c := code_edit.text.strip_edges().to_upper()
	if Net.web() and c.length() != 5:
		status_l.text = "The code has 5 letters and numbers."
		return
	Game.code = c
	Net.join(c)
	_waiting("Connecting...")


func _waiting(text: String) -> void:
	_clear()
	page.add_child(UI.Stamp.new("PENDING", 90, 0.06))
	status_l = _text(text, UI.bold, 34)
	_text("When the host starts the day you'll be told your part.", UI.body, 26, UI.MUTED)
	UI.button("LEAVE", func():
		Net.close()
		hello_sent = false
		_title(), page)


# --------------------------------------------------------------- network

func _net_opened(_id: String) -> void:
	if Game.mode == Game.Mode.HOST and status_l and is_instance_valid(status_l):
		status_l.text = "The town is open."


func _peer_joined(peer: String) -> void:
	if Game.mode == Game.Mode.CLIENT:
		Game.host_peer = peer
		Net.send(peer, {"k": "hello", "watch": Game.watching})
		hello_sent = true
		if status_l and is_instance_valid(status_l):
			status_l.text = "You're in. Waiting for the day to start."


func _peer_left(peer: String) -> void:
	if Game.mode == Game.Mode.HOST:
		Game.players = Game.players.filter(func(p): return p.peer != peer)
		Game.watchers.erase(peer)
		_refresh()
	elif peer == Game.host_peer:
		Net.close()
		_title()


func _net_message(peer: String, d: Dictionary) -> void:
	if Game.mode == Game.Mode.HOST:
		if d.get("k") == "hello" and Game.players.size() + Game.watchers.size() < 45:
			Game.players = Game.players.filter(func(p): return p.peer != peer)
			Game.watchers.erase(peer)
			if d.get("watch", false):
				Game.watchers.append(peer)
			else:
				Game.players.append({"peer": peer})
			_refresh()
			if test_host > 0 and Game.players.size() >= test_host:
				_start.call_deferred()
	elif d.get("k") == "role":
		Game.role = d.role
		Game.seat = int(d.get("seat", 0))
		get_tree().change_scene_to_file("res://scenes/round.tscn")


func _net_failed(why: String) -> void:
	if status_l and is_instance_valid(status_l):
		status_l.text = "Network problem: %s" % why


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not Net.active:
		_title()
