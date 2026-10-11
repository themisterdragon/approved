# Approved: design notes

## The idea

A class game that puts students inside the kind of state the novels show:
watched, ruled by a wall that changes, unsure who to trust. Not a quiz with a
theme on top; the mechanics *are* the themes, so the debrief has something
real to talk about.

## Where it comes from (and what it must not take)

*1984* and *Animal Farm* are not public domain in the US (until about 2044
and 2041). Themes and ideas are free to use; names, text and coined words
are not ours to borrow. So the game's town, rules, slogans and people are
original, and `tools/check_original.py` keeps the books' names and coined
words out of the code (it runs on every commit). Only teacher material
about the books (`data/questions.json`, `data/prompts.json`) names them.

What each mechanic evokes:

| In the game | In the novels |
|---|---|
| The wall in Assembly Square; amendments the townsfolk obey at once | The barn's commandments, changed overnight |
| Citizens know rules only as they last read them | Doubting one's own memory; the record rewritten |
| Cameras, and a board that shows what they see | Being watched, and knowing it |
| Hurrying, nodding, gathering as tells | Facecrime: giving yourself away |
| Questioning on the reading, pages confiscated | Interrogation; what you hold is taken |
| Taking the innocent, on the record | The cost of a state's certainty |
| Passing a page to a stranger | Trust, and its risks |

## Tone

Dark but classroom-safe: night, rain, sodium lamps, a red Bureau with an
eye, slogans in a cold voice. Nobody is hurt; "taken for questioning" means
answering questions on the reading. Students are numbers, never names.

## Roles

- **The Bureau**: the teacher, one student, or a council of 2-3 (each seat
  moves its own cameras; any seat may take or amend).
- **Citizens**: everyone else.
- **Watchers**: the board, and students who'd rather not play.
- **Practice**: one player against robots (robot Bureau or robot citizens).

## Balance (first pass)

- Pages are scarce at dawn (one per citizen plus two) and turn up every
  25 s, up to three per citizen; searching takes 2.5 s, slipping out 6 s
  unseen.
- Warrants: 2 + council seats, one more every 90 s (up to 6).
- Amend once every 45 s. Dusk at 65% of the day (50% under one curfew
  wording).
- Robot citizens only notice pages near them; the robot Bureau watches the
  exits and takes anyone over 65% suspicion.

## Next

- Informants: offer a citizen a reward to name another.
- Broadcasts: the Bureau puts a message on every screen.
- Sound: rain, a hum, the bell, the PA.
- Phones: on-screen walking stick and bigger buttons.
- A how-to-play walkthrough for the first round.
- Self-hosted matchmaking for strict school networks.
