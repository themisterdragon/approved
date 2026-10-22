class_name Debrief
extends ColorRect
## After the day: what happened, in order, and questions to talk about.
## The wall as first posted beside the wall at the end; every rule change,
## every person taken (innocent or not), every escape; each citizen's
## numbers; and discussion prompts for the novels and civics.

var summary: Dictionary
var is_host: bool
var on_again: Callable
var on_menu: Callable


func _init(s: Dictionary, host: bool, again: Callable, menu: Callable) -> void:
	summary = s
	is_host = host
	on_again = again
	on_menu = menu
	color = Color(UI.INK, 0.97)
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 30)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	var s := summary
	page.add_child(UI.Stamp.new("THE CITY REMEMBERS" if s.free else "ORDER IS KINDNESS", 64, -0.05 if s.free else 0.05))
	var line := UI.label("%d of %d citizens slipped out.   Citizens taken for questioning: %d.   Innocent people taken: %d." % [
		int(s.escaped), int(s.citizens), int(s.taken), int(s.innocents)], UI.bold, 30, UI.PAPER, page)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# the wall, then and now
	var walls := HBoxContainer.new()
	walls.alignment = BoxContainer.ALIGNMENT_CENTER
	walls.add_theme_constant_override("separation", 30)
	page.add_child(walls)
	for side in [["THE WALL AT DAWN", s.rules_start], ["THE WALL AT NIGHTFALL", s.rules_end]]:
		var p := UI.panel(walls, 0.6)
		var v := VBoxContainer.new()
		p.add_child(v)
		UI.label(side[0], UI.head, 28, UI.PAPER, v)
		for r in side[1]:
			var changed: bool = side[0].ends_with("NIGHTFALL") and not r in s.rules_start
			var l := UI.label(("• " + r) + ("   (changed)" if changed else ""), UI.bold if changed else UI.body, 22, UI.RED_BRIGHT if changed else UI.PAPER, v)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 680
	# what happened, in order
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 30)
	page.add_child(cols)
	var tl := UI.panel(cols, 0.6)
	var tv := VBoxContainer.new()
	tl.add_child(tv)
	UI.label("THE RECORD", UI.head, 28, UI.PAPER, tv)
	var shown := 0
	for e in s.log:
		if e[2] in ["amend_public", "taken_public", "escape_public", "bell"]:
			continue
		var bad: bool = e[2] in ["innocent", "taken", "amend"]
		var l := UI.label("%d:%02d   %s" % [int(e[0]) / 60, int(e[0]) % 60, e[1]], UI.body, 21, UI.RED_BRIGHT if bad else UI.MUTED, tv)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 820
		shown += 1
	# each citizen's day
	var ct := UI.panel(cols, 0.6)
	var cv := VBoxContainer.new()
	ct.add_child(cv)
	UI.label("THE CITIZENS", UI.head, 28, UI.PAPER, cv)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	cv.add_child(grid)
	for h in ["Citizen", "Pages", "Passed", "Nods", "Taken", "Out?"]:
		UI.label(h, UI.bold, 20, UI.PAPER, grid)
	for r in s.stats:
		for v in [str(int(r[0])), str(int(r[1])), str(int(r[2])), str(int(r[3])), str(int(r[4])), "yes" if r[5] else "no"]:
			UI.label(v, UI.body, 20, UI.MUTED, grid)
	# talk about it
	var pr := UI.panel(page, 0.6)
	pr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pv := VBoxContainer.new()
	pr.add_child(pv)
	UI.label("TALK ABOUT IT", UI.head, 28, UI.PAPER, pv)
	var prompts = JSON.parse_string(FileAccess.get_file_as_string("res://data/prompts.json"))
	var lines: Array = []
	if prompts is Dictionary:
		lines.append_array(prompts.game)
		for set_name in Game.sets:
			lines.append_array(prompts.get(set_name, []))
	for p in lines:
		var l := UI.label("• " + p, UI.body, 22, UI.PAPER, pv)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 1380
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	page.add_child(row)
	if is_host:
		UI.button("ANOTHER DAY (NEW RULER)" if Game.mode == Game.Mode.HOST else "ANOTHER DAY", on_again, row, Vector2(520, 70), 30)
		UI.button("MENU", on_menu, row, Vector2(260, 70), 30)
	else:
		UI.label("Waiting for the host to start another day.", UI.body, 26, UI.MUTED, row)
	await get_tree().process_frame
	for b in row.get_children():
		if b is Button:
			b.grab_focus()
			break
