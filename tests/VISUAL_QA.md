# Visual QA: before any preview goes to Fianso

Fianso catches visual bugs by eye. QA's job is to catch them first.

## 1. Run the automatic check (about 15 seconds)

    godot --headless --script res://tests/visual_qa_test.gd

With pictures of every problem (saved to `user://visual_qa/`):

    xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --script res://tests/visual_qa_test.gd

It sweeps a person and the dog over every spot they can stand on, facing 8
ways, with the real HD frames, on level 1 (both floors) and level 2.

| Check | Rule | Result |
|---|---|---|
| Hidden under furniture | Furniture is never drawn over a player or an enemy | FAIL |
| Drawn over furniture | A player or an enemy is never drawn over furniture art | WARN: look at the pictures (cut-out pieces carry a little floor at their edges) |
| Dogs | Dogs may go under tables (they are shorter) | listed only |
| Real-life sizes | Furniture, doors and the dog vs a person, using the size table in the test (`SIZES`) | FAIL if more than 30% off, WARN if 15-30% |
| Reachable | Every enemy and weapon can be walked up to; areas nobody can enter are listed | FAIL / WARN |
| Animations | Walk frames don't jump (sliding, jitter); every animation is the same size as walking | WARN |
| Walls | No person or dog drawn into a wall walking; an attack tucked behind a wall is a WARN, a blade showing on the far side FAILs | FAIL / WARN |
| Dead bodies | Every dead pose and death frame (people and dogs), turned every way, wherever someone can die: never in a wall; never half under a sofa, cabinet or plant | FAIL / WARN |
| Pixel size | People, dogs, rooms and weapons on the floor all drawn with the same pixel size | FAIL |
| Weapons | Dropped or thrown weapons stop with all of them outside the wall; weapons placed in the level lie clear of walls | FAIL |
| Blood | A spurt can't fly further than the thinnest wall (or it lands in the next room) | FAIL |
| Rooms | Each room (found from the floor shape, cut at doorways) against real homes: bedroom, bathroom, kitchen, office, living room; walkways at least 0.9 m | WARN: look at the map |

Do not send a preview while anything says FAIL, unless Fianso already knows
about that FAIL.

## 2. Look at the preview yourself

Seen from above, a person is about 0.5 m across the shoulders. Compare
everything with that:

- [ ] A person looks smaller than a fridge or a bed, about as wide as a chair, and narrower than a door.
- [ ] Nobody's head, body or legs disappear under a sofa, a table or a wall.
- [ ] Nobody stands on top of a sofa, a table or a bed.
- [ ] People face where they walk or aim. No backwards walking, no bodies turned sideways to their legs.
- [ ] Facing up, a person doesn't look like he's lying on the floor (the art is drawn from a high angle, so this is the case to watch).
- [ ] Feet don't slide: the walk speed matches the steps.
- [ ] Arms and hands look natural: two hands on two-handed guns, no extra or missing limbs, nothing bending the wrong way.
- [ ] Weapons sit in the hand, not floating beside it.
- [ ] Bodies, blood and pickups lie on the floor, not on top of furniture.
- [ ] The dog looks like a doberman next to a person: about twice as long as a person is wide.
- [ ] Nothing pops bigger or smaller when switching animation (idle, walk, attack).
- [ ] The outline and the implant code stay on the character, never on the floor around him.
- [ ] Touch controls don't cover the action in the middle of the screen.

- [ ] Rooms look like real rooms: a bathroom isn't the size of a lounge, a corridor is wide enough for two people to pass.
- [ ] No stretched or cut art, seams in the floor, doubled wall lines, or furniture floating or facing into a wall.

## 3. Preview pictures made outside the game

A picture put together by hand (art previews, before/after sheets) must
show everything where it could really be in the game: bodies, blood and
weapons on open floor, never over a wall or a painting. QA looks at every
such picture before it goes to Fianso.

Write what you find in plain words, with a picture, before the preview goes out.
