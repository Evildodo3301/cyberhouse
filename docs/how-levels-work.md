# How a level is built (plain-language guide)

Every house in Cyberhouse is written as **text**, not placed by hand. Open a
level scene (for example `scenes/levels/level_02.tscn`, the penthouse), click
the **LevelMap** node, and you will see two big text boxes in the Inspector:
**Layout** and **Furniture**. Change the letters, run the game, and the house
changes.

## 1. The layout: one letter = one floor tile

Each letter is a square of 8 x 8 pixels (a character is about 16 pixels wide,
so two letters).

| Letter | What it is |
|---|---|
| `#` | wall |
| `W` | window wall: glass with the city behind it (blocks like a wall) |
| `S` | stairs (a block of S's is one end of a staircase) |
| `x` | floor with furniture on it (picture levels: the piece itself blocks) |
| `~` | pool water: you can't walk in it, but bullets fly over it |
| `.` | floor |
| `D` | swinging door. 4 in a row = one door. 8 in a row = a **double door** |
| `o` | open doorway (an arch, no door) |
| `P` | where you start |
| `E` | the exit (opens when everyone is dead) |
| `M` `C` `G` `F` | enemies: machete, pistol, machine gun, fists |
| `K` | doberman |
| `g` `m` `u` | pistol, machete, machine gun lying on the floor |

The game works out the rooms by itself: any floor area closed off by walls
and doors is one room.

### Two floors in one level

Draw both floors in the same Layout box, one above the other, with at least
**20 rows of spaces** (open sky) between them so you never see the other
floor on screen. The floor at the top is **floor 1**.

Put a block of `S` on each floor where the stairs are, then link the two
blocks with one line in the furniture list:

```
stairs 40 12 40 90     the S block at tile 40,12 goes to the S block at 40,90
```

Walk onto one end and you come out on the other floor, with a "FLOOR 2"
banner. Step off the stairs before you can take them back. Enemies stay on
their own floor. Make the Gore node's area_size cover the whole map
(width x height in pixels, both floors).

### Floors as separate maps (level 1, the mansion)

Level 1 does it the other way: each floor is its own scene
(`level_01.tscn` and `level_01_floor2.tscn`), so dying on floor 2 restarts
floor 2 only. Floor 1's exit is its staircase: a block of `E` on the stairs
plus the line `exit_walk west` (the way you walk up). Once everyone is dead,
stepping on it makes the hero walk up the stairs on his own while the screen
fades, then a loading screen shows the picture in the level's
`stairs_picture` box (Fianso's drawing; a "UP THE STAIRS..." stand-in until
then), and floor 2 (the level's `next_floor`) starts at its `P`. Score,
combo, time and the weapon in your hands carry over. Floor 2's own `E`
stairs with `exit_walk` end the level instead, since it has no `next_floor`.

No picture yet? `x` tiles then stand in as plain dark blocks, so the floor
can be played before its art is approved.

### Levels built from a picture (level 1)

Level 1 is Fianso's own drawing of the house. In the LevelMap node:

* **Picture**: the whole floor drawn as one image (walls, floors, paintings).
* **Picture pieces**: a JSON list of the furniture cut out of that drawing.
  Each piece has its own image in `pieces/`, the spot where it stands
  (`sort_y`, its base, for depth) and the box that blocks (`collision`).
* **Layout** still says what blocks (`#`, `~`) and where people, weapons,
  doors and stairs go. Walls are drawn again on top of the blood, so blood
  never covers a wall or a painting.

Files: `assets/levels/mansion/floor1/`.

## 2. The furniture list: one thing per line

```
white_sofa_long 53 40     a sofa whose top-left corner is on tile 53, 40
floor_checker 10 10       the room around tile 10, 10 gets the checker floor
painting_gold 54 30 up    a painting on the north wall, starting at tile 54, 30
```

* **Floors:** `floor_marble`, `floor_dark_marble`, `floor_bath`,
  `floor_checker` (black and white kitchen tiles), `floor_herringbone` (dark
  wood parquet). Rooms without one get plain wood.
* **Furniture** pictures live in `assets/levels/furniture/`, one PNG each.
  The name in the list is the file name.
* **Enemies:** `patrol 55 38 55 19` makes the enemy on tile 55,38 walk to
  55,19 and back (more points = a loop). `face 12 21 west` sets which way an
  enemy faces at the start.
* **One-way doors:** `door_out 43 15 up` makes that door only swing up
  (outward). 6 or more D's in a row make a double door.
* **Wall decor** (paintings, sconces, clocks, wood panels) lives in
  `assets/levels/decor/`. The fourth word says which wall it hangs on:
  `up` = north wall, `down` = south, `left` = west, `right` = east. The game
  turns the picture to face the room.

## 3. What is in front of what (depth)

Things are stacked in layers, bottom to top:

1. the floor
2. rugs and doormats
3. blood and bodies
4. **dogs** (they're short: they can run under tables and desks)
5. **furniture**, sorted by how far down the screen it stands (whichever
   piece is lower is drawn in front: "Y-sorting")
6. **people**, always on top of furniture, so nobody ever looks like they
   slip under a sofa or a table. People also keep a few pixels clear of
   every piece's drawing (a "keep-out" box, `KEEP_OUT` in level_map.gd),
   because the high-angle HD frames reach further than the 7 px body. So a
   person's picture never covers the furniture either. Bullets, enemies'
   eyes and dogs ignore the keep-out.
7. walls
8. wall decor (paintings etc.), so nobody is ever drawn on top of a painting
9. bullets, then the crosshair

## 4. What blocks you (collision)

* Walls, windows and closed doors block people, dogs and bullets.
* Most furniture blocks with its whole picture.
* Tall things that are wider at the top (plants, lamps, statues) only block
  at their **base**, so you can brush past the leaves. These base boxes are
  listed in `FOOTPRINTS` at the top of `scripts/levels/level_map.gd`.
* Rugs and wall decor never block.

Enemies find their way round all of this by themselves.

## 5. Adding a new piece of furniture

1. Put the picture in `assets/levels/furniture/`, for example `safe.png`.
2. Add one line to `FANCY_FURNITURE` in `scripts/levels/level_map.gd`:
   `"safe": true,` (`true` = solid, `false` = you walk over it like a rug).
3. If only its base should block, add its base box to `FOOTPRINTS`.
4. Use it in a level: `safe 12 40`.

## 6. Checking a level

The tests check every level automatically: every enemy can reach you, no
enemy or weapon starts inside furniture, no furniture sits where a door
swings, and decor really hangs on walls.

```
godot --headless --script res://tests/level_02_test.gd
```
