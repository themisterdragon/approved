extends Node
## What the menus decided, for the round to read, and what's carried from
## one round to the next (the class code, who's playing, the last debrief).

enum Mode { PRACTICE_CITIZEN, PRACTICE_RULER, HOST, CLIENT }

var mode := Mode.PRACTICE_CITIZEN
var ruler_mode := "teacher"   # (host) "teacher", "student" or "council"
var council := 1              # seats when the ruler is a council (2 or 3)
var minutes := 7
var sets := ["1984", "Animal Farm", "Civics"]
var code := ""
var rules := {}               # the rules the ruler posted for this round
var board := "eyes"           # (host) what the board and watchers see: "eyes" (the Bureau's
                              # cameras, live), "delayed" (everyone, 60 s behind), "streets"
var watching := false         # (players) this screen joined just to watch

# a class game
var role := "citizen"         # this screen: "ruler", "citizen" or "public"
var seat := 0                 # (ruler) council seat
var host_peer := ""           # (players) the host's peer id
var players: Array = []       # (host) [{peer}] everyone who joined to play
var watchers: Array = []      # (host) peers who joined just to watch
var rulers: Array = []        # (host) peers ruling this round ("" = the host itself)
var last_rulers: Array = []   # (host) so the next round can pick someone else
var summary := {}             # the last round's debrief


func questions() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/questions.json"))
	var out := []
	if d is Dictionary:
		for s in sets:
			out.append_array(d.sets.get(s, []))
	return out


func question_sets() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/questions.json"))
	return d.sets.keys() if d is Dictionary else []
