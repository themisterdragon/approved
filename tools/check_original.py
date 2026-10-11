#!/usr/bin/env python3
"""Keep the game's own world original.

1984 and Animal Farm aren't in the public domain in the US, so the town,
its rules, slogans and characters must not borrow their names or coined
words. Teacher material about the books (data/questions.json and
data/prompts.json) may name them; everything else may not. Titles of the
books are fine (they name the question sets). Runs from the pre-commit hook.
"""
import re, subprocess, sys

WORDS = [r"Big Brother", r"Winston", r"\bJulia\b", r"O'Brien", r"Goldstein", r"Oceania", r"Eurasia", r"Eastasia",
         r"Ingsoc", r"Newspeak", r"doublethink", r"thoughtcrime", r"Thought Police", r"telescreen", r"Minitrue",
         r"Miniluv", r"Minipax", r"Miniplenty", r"Room 101", r"Victory Gin", r"Napoleon", r"Snowball", r"Squealer",
         r"\bBoxer\b", r"Manor Farm", r"Old Major", r"Sugarcandy", r"four legs", r"more equal", r"Two Minutes Hate",
         r"memory hole", r"unperson", r"Airstrip One", r"Brotherhood"]
ALLOWED = {"data/questions.json", "data/prompts.json", "tools/check_original.py", "docs/DESIGN.md"}
TEXT = (".gd", ".tscn", ".json", ".md", ".txt", ".js", ".html", ".py", ".cfg", ".godot")

root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
args = ["ls-files"] if "--all" in sys.argv else ["diff", "--cached", "--name-only", "--diff-filter=ACMR"]
files = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True).stdout.split()
pat = re.compile("|".join(WORDS), re.I)
bad = []
for f in files:
    if f in ALLOWED or not f.endswith(TEXT) or f.endswith(".min.js"):
        continue
    with open(f"{root}/{f}", encoding="utf-8", errors="ignore") as fh:
        for n, line in enumerate(fh, 1):
            m = pat.search(line)
            if m:
                bad.append(f"{f}:{n}: '{m.group()}'")
if bad:
    sys.exit("originality check failed (keep the books' names and coined words out of the game):\n  " + "\n  ".join(bad))
print("originality check passed")
