#!/usr/bin/env python3
"""Lay out the town and write data/town.json.

The town is a 60 x 34 grid of 32-pixel tiles, so the whole of it fits one
1920 x 1088 screen (the ruler's view). Run again after changing a layout
below: python3 -I tools/make_town.py

Tiles:
  W  the city wall           #  a building (H housing, F works, M market,
  .  street                     B the Bureau, Q old houses: all solid)
  ,  the square's paving     R  the rule wall (solid)
  o  old quarter cobbles     T  a tree (solid)
  p  park grass              G  the gate (a way out)
  C  the culvert (the other way out, hidden in the old quarter)
"""
import json, os, random

W, H = 60, 34
grid = [["." for _ in range(W)] for _ in range(H)]


def rect(x, y, w, h, c):
    for j in range(y, y + h):
        for i in range(x, x + w):
            grid[j][i] = c


# the wall all round, with the gate in the south and the culvert in the west
rect(0, 0, W, 1, "W"); rect(0, H - 1, W, 1, "W"); rect(0, 0, 1, H, "W"); rect(W - 1, 0, 1, H, "W")
grid[H - 1][29] = grid[H - 1][30] = "G"
grid[29][0] = "C"

# housing (north west): rows of blocks
for by in (2, 7):
    for bx in (2, 8, 14):
        rect(bx, by, 5, 3, "H")
rect(2, 15, 5, 3, "H"); rect(8, 15, 5, 3, "H"); rect(14, 15, 6, 3, "H")

# the works (north east): long sheds and a chimney block
rect(40, 2, 8, 4, "F"); rect(50, 2, 8, 4, "F"); rect(40, 8, 18, 3, "F")

# the square (middle): paving, the rule wall at its head, trees at the corners
rect(22, 12, 16, 10, ",")
rect(28, 13, 4, 1, "R")
for t in ((23, 13), (36, 13), (23, 20), (36, 20)):
    grid[t[1]][t[0]] = "T"

# the market (east of the square): stalls in a hall
rect(41, 14, 7, 3, "M"); rect(50, 14, 8, 3, "M"); rect(41, 19, 17, 2, "M")

# the Bureau (south east): one great block
rect(42, 24, 15, 7, "B")

# the park (south middle): grass, paths, trees
rect(22, 24, 16, 8, "p")
rect(22, 27, 16, 1, "."); rect(29, 24, 2, 9, ".")
random.seed(7)
for _ in range(18):
    x, y = random.randrange(22, 38), random.randrange(24, 32)
    if grid[y][x] == "p":
        grid[y][x] = "T"

# the old quarter (south west): cobbles and crooked little houses
rect(1, 20, 19, 13, "o")
random.seed(3)
for _ in range(26):
    w, h = random.randint(2, 4), random.randint(1, 3)
    x, y = random.randint(2, 18 - w), random.randint(21, 31 - h)
    rect(x, y, w, h, "Q")
# keep a winding lane to the culvert open
for x in range(1, 12):
    grid[29][x] = "o"
for y in range(20, 30):
    grid[y][11] = "o"
rect(1, 20, 19, 1, "o")  # its edge on the avenue

# the avenues: kept clear across the town
rect(1, 12, 20, 1, "."); rect(1, 22, 21, 1, "."); rect(21, 1, 1, 32, "."); rect(38, 1, 1, 32, ".")
rect(39, 12, 20, 1, "."); rect(39, 22, 20, 1, ".")

# where things are, for the rules (x, y, w, h in tiles)
districts = {
    "housing": [1, 1, 20, 18],
    "works": [39, 1, 20, 11],
    "square": [22, 12, 16, 10],
    "market": [39, 13, 20, 9],
    "bureau": [39, 23, 20, 10],
    "park": [22, 23, 16, 10],
    "old": [1, 20, 19, 13],
}
names = {
    "housing": "the Housing Blocks", "works": "the Works", "square": "Assembly Square",
    "market": "the Ration Hall", "bureau": "the Bureau", "park": "the Gardens of Plenty",
    "old": "the Old Quarter",
}

out = {"w": W, "h": H, "tile": 32, "rows": ["".join(r) for r in grid], "districts": districts, "names": names}
path = os.path.join(os.path.dirname(__file__), "..", "data", "town.json")
with open(path, "w") as f:
    json.dump(out, f, indent=1)
print("\n".join(out["rows"]))
