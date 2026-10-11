extends Node
## Test-only screenshots, for checking the game without a person at the screen.
## Off unless the game is started with user args, e.g.:
##   godot -- --shot=/tmp/out --at=30,90 --press=60:ui_down,70:joy0,80:key:Enter
## saves shot_30.png and shot_90.png, presses ui_down at frame 60, gamepad
## button 0 (A / Cross) at 70 and the Enter key at 80, then quits.

var out := ""
var at: Array[int] = []
var presses := {}
var frame := 0
var t0 := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			out = arg.substr(7)
		elif arg.begins_with("--at="):
			for n in arg.substr(5).split(","):
				at.append(int(n))
		elif arg.begins_with("--press="):
			for p in arg.substr(8).split(","):
				var at := p.find(":")
				presses[int(p.left(at))] = p.substr(at + 1)
	set_process(out != "")
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	frame += 1
	if presses.has(frame):
		var what: String = presses[frame]
		for down in [true, false]:
			var ev: InputEvent
			if what.begins_with("joy"):
				ev = InputEventJoypadButton.new()
				ev.button_index = int(what.substr(3))
				ev.pressed = down
			elif what.begins_with("key:"):
				ev = InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(what.substr(4))
				ev.physical_keycode = ev.keycode
				ev.pressed = down
			else:
				ev = InputEventAction.new()
				ev.action = what
				ev.pressed = down
			Input.parse_input_event(ev)
	if frame in at:
		get_viewport().get_texture().get_image().save_png("%s/shot_%d.png" % [out, frame])
	if frame == 60:
		t0 = Time.get_ticks_msec()
	if at.is_empty() or frame >= at.max():
		if frame > 60:  # (frames drawn per second after the first 60, for comparing builds)
			print("dev_shot fps: %.1f, triangles %d, draw calls %d" % [(frame - 60) * 1000.0 / maxf(Time.get_ticks_msec() - t0, 1),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		get_tree().quit()
