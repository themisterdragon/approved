# Approved

**A class game about rules, watching, and getting out.**

One player is the Bureau. Everyone else is a citizen, hidden in a crowd of
townsfolk who look exactly like them. Citizens look for torn pages and try
to slip out of a walled town. The Bureau watches through a few cameras,
posts the rules, and quietly changes them. Afterwards the class gets the
record of what happened: who was taken, who got out, how the rules changed,
and questions to talk about.

It was made for a unit on *1984* and *Animal Farm*, and it pairs with
high-school civics. The town, its rules and its people are all original;
the novels stay in the students' hands, and the game gives them something
to compare.

**Play in the browser:** https://themisterdragon.github.io/approved/

## How a round works

- **The Bureau** posts three rules from a set of cards (curfew, no
  hurrying, no gathering, a closed district, report to your post at the
  bell), choosing how each is worded. During the day it can **amend** a
  rule. The townsfolk obey the new wording at once. Citizens only know a
  rule as they last read it on the wall in Assembly Square.
- **Cameras** show the Bureau a few circles of the town. Anyone breaking a
  rule on camera is circled. Taking someone for questioning costs a
  warrant, and taking an innocent person goes on the record.
- **Citizens** walk like everyone else, search for torn pages (three to get
  out), nod to signal one another and pass pages to people they trust.
  The way out is the gate in the south wall, or the old culvert in the
  west.
- **Taken for questioning?** A citizen answers questions on the reading
  (1984, Animal Farm or civics; teachers can edit or add questions in
  `data/questions.json`). Two right answers and they're let go, without
  their pages.
- **The debrief** puts the wall at dawn beside the wall at nightfall, lists
  every taking, amendment and escape in order, shows each citizen's day,
  and offers discussion prompts (`data/prompts.json`).

## For teachers

- **Host** from your computer: choose who rules (you, one student, or a
  council of two or three; the game picks students at random and rotates
  them), how long a day lasts (5, 7 or 9 minutes), and which question sets
  to use. Students open the page, choose *Join a class game* and type the
  class code.
- **A 45-minute period** fits a practice day and a second day for review,
  each with time to talk afterwards.
- **The board:** the host's screen can go on the ViewBoard. You choose what
  it shows: the Bureau's cameras live (the ruler learns nothing new), the
  whole town a minute behind with citizens labelled (more to follow, but a
  ruler could glean where people were), or empty streets. It never shows
  the wall's current wording, so citizens still have to go and read it.
  Students who'd rather not play can choose *Just watch*. If you are the
  ruler, keep your own screen to yourself and put a watcher on the board.
- **Practice** as a citizen (against a robot Bureau) or as the Bureau
  (against robot citizens), no class needed.
- Nobody is named: citizens are numbers, and nothing is stored. See
  [PRIVACY.md](PRIVACY.md).

## Standards it can support

Check these against your own state's standards; the debrief prompts are
written to start the discussion, not to replace your lesson.

- **ELA (CCSS, grades 9-12):** themes and how they develop (RL.9-10.2,
  RL.11-12.2), an author's choices about structure and character
  (RL.9-10.3, RL.11-12.3), point of view and rhetoric, including
  propaganda (RI.9-10.6, RI.11-12.6), collaborative discussion
  (SL.9-10.1, SL.11-12.1), and argument writing from the debrief
  (W.9-10.1, W.11-12.1).
- **Civics (C3 Framework, D2.Civ, grades 9-12):** limits on government
  power, rights and the rule of law, and how people use and challenge laws.
  The rule cards map onto the First Amendment (assembly), the Fourth
  (searches), due process, and the ban on ex post facto laws.

## The look

The town is drawn in code, seen from above and a little to the south:
`scripts/town_art.gd` paints the streets, buildings, gardens and wall once,
and `scripts/figures.gd` draws the townsfolk. There are twelve kinds of
people (a works hand in a flat cap, a clerk with a briefcase, a baker, an
old man with a stick, two with umbrellas...), and every citizen is one of
them, so three or four people in town always look like you.

## Controls

Keyboard: WASD or arrows to walk (or click where to go), Shift to hurry,
Space to nod, F to pass a page, 1-4 to answer. The Bureau: click one of
your cameras then a street to move it; click a person on camera, then
*Take for questioning* (or Enter); the mouse wheel zooms in on the town,
and arrows, WASD or a right-button drag move round it. Tab folds the wall
card away. Touch screens work by tapping.

## Building it

Godot 4.5 or later (made with 4.7), Compatibility renderer. Open the folder
in the editor, or export with the presets in `export_presets.cfg`.
`tools/build_web.sh` makes the browser build; `tools/make_town.py` lays out
the town. Commits run `tools/check_privacy.py` and `tools/check_original.py`
(the second keeps the novels' names and coined words out of the game's own
world).

## Licence

GPL-3.0 (see [LICENSE](LICENSE)). Fonts and libraries: see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
