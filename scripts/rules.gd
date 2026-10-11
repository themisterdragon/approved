class_name Rules
## The rule cards. The ruler posts three before a round and may amend one
## now and then; each amendment is another wording of the same rule, and
## changes what the townsfolk do (they always obey the wall as it reads now)
## and what gets a person flagged. Citizens only know a rule as they last
## read it on the wall in Assembly Square.

const CARDS := {
	"curfew": {
		"title": "Curfew",
		"texts": [
			"After dusk, every citizen is indoors in the Housing Blocks.",
			"After the second bell, every citizen is indoors in the Housing Blocks.",
			"After dusk, every citizen is indoors. Workers of the night shift excepted.",
		],
		"why": "Limits on where and when people may go.",
	},
	"walk": {
		"title": "Calm",
		"texts": [
			"Walk. Haste suggests guilt.",
			"Keep moving. To linger is to plot.",
		],
		"why": "Rules about how people behave in public.",
	},
	"gather": {
		"title": "Assembly",
		"texts": [
			"No more than two citizens together.",
			"No citizen walks beside another.",
		],
		"why": "Limits on assembly: who may meet, and how many.",
	},
	"closed": {
		"title": "Closed District",
		"texts": [
			"The Old Quarter is closed.",
			"The Gardens of Plenty are closed.",
			"The Ration Hall is closed.",
		],
		"districts": ["old", "park", "market"],
		"why": "Movement restricted by district.",
	},
	"posts": {
		"title": "Posts",
		"texts": [
			"At the bell, every citizen stands at a post in the Works.",
			"At the bell, every citizen stands in Assembly Square.",
		],
		"why": "Required presence: labour and loyalty on a schedule.",
	},
}

const ORDER := ["curfew", "walk", "gather", "closed", "posts"]
const DEFAULT := {"curfew": 0, "walk": 0, "closed": 0}  # a ready-made set
const PICK := 3          # rules posted per round
const AMEND_EVERY := 45.0  # seconds between amendments
const BELL_EVERY := 70.0
const BELL_LONG := 16.0
const BELL_GRACE := 9.0  # time to reach your post before it counts


static func text(rule: String, variant: int) -> String:
	var t: Array = CARDS[rule].texts
	return t[clampi(variant, 0, t.size() - 1)]


static func wall_lines(rules: Dictionary) -> Array:
	var out := []
	for r in ORDER:
		if rules.has(r):
			out.append(text(r, int(rules[r])))
	return out
