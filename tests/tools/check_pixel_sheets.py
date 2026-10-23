"""QA: checks a pixel-art character set before it goes to Fianso.

    python3 tests/tools/check_pixel_sheets.py <folder with pixel_anims.json>

Looks for: sheets the wrong size, sprites cut off at a cell edge, half-see-through
or lonely stray pixels, heads changing size between sheets of one character,
walk loops that jump, bodies off their turning centre, and real-life size
(a person 0.5 m across the shoulders = 15 room px; a doberman ~1.1 m = 33 px).
"""
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

ROOM_PER_SPRITE_PX = 0.5   # README: 1 sprite pixel = 0.5 room pixel
PX_PER_M = 30.0            # room px per metre (person 0.5 m = 15 px)
folder = Path(sys.argv[1])
anims = json.loads((folder / "pixel_anims.json").read_text())["anims"]
fails, warns = [], []


def frames(name):
    a = anims[name]
    sheet = Image.open(folder / a["file"]).convert("RGBA")
    return sheet, [sheet.crop((i * a["cell_w"], 0, (i + 1) * a["cell_w"], a["cell_h"])) for i in range(a["frames"])]


def opaque(im):
    w, h = im.size
    px = im.load()
    return {(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 0}


def biggest_blob(points):
    points, best = set(points), set()
    while points:
        todo, blob = [points.pop()], set()
        while todo:
            p = todo.pop()
            blob.add(p)
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (p[0] + d[0], p[1] + d[1])
                if q in points:
                    points.remove(q)
                    todo.append(q)
        if len(blob) > len(best):
            best = blob
    return best


def is_head(who, c):
    r, g, b, a = c
    if a == 0:
        return False
    if who == "enemy":   # bald: skin tone
        return r > 140 and g > 95 and b > 60 and r > g > b
    if who == "hero":    # brown hair (warm), the suit is cool grey-black
        return r >= b + 8 and r >= g and r < 150
    return False


heads = {}
for name, a in sorted(anims.items()):
    who = name.split("_")[0]
    sheet, cells = frames(name)
    if sheet.size != (a["cell_w"] * a["frames"], a["cell_h"]):
        fails.append(f"{name}: sheet is {sheet.size}, expected {a['frames']} x {a['cell_w']} by {a['cell_h']}")
    alphas = Counter(c[3] for c in sheet.get_flattened_data())
    half = sum(n for al, n in alphas.items() if 0 < al < 255)
    if half:
        warns.append(f"{name}: {half} half-see-through pixels (pixel art should be fully on or off)")
    colours = Counter(c for c in sheet.get_flattened_data() if c[3] > 0)
    rare = [c for c, n in colours.items() if n <= 2]
    if len(rare) > 3:
        warns.append(f"{name}: {len(colours)} colours, {len(rare)} used only once or twice (possible stray colours)")
    centres, widths, head_centres = [], [], []
    for i, cell in enumerate(cells):
        pts = opaque(cell)
        if not pts:
            fails.append(f"{name} frame {i}: empty")
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        edges = [side for side, hit in (("left", min(xs) == 0), ("top", min(ys) == 0), ("right", max(xs) == a["cell_w"] - 1), ("bottom", max(ys) == a["cell_h"] - 1)) if hit]
        if edges:
            fails.append(f"{name} frame {i}: touches the cell edge ({', '.join(edges)}), may be cut off")
        lonely = [p for p in pts if not any((p[0] + dx, p[1] + dy) in pts for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)]
        if lonely:
            warns.append(f"{name} frame {i}: {len(lonely)} lonely pixel(s) at {lonely[:4]}")
        centres.append((sum(xs) / len(xs), sum(ys) / len(ys)))
        widths.append(max(xs) - min(xs) + 1)
        if who in ("hero", "enemy") and "blood" not in name:
            px = cell.load()
            head = biggest_blob([p for p in pts if is_head(who, px[p])])
            if len(head) > 8:
                # Top 60% of the blob only, so fists held up by the face don't count.
                top = min(p[1] for p in head)
                cut = top + 0.6 * (max(p[1] for p in head) - top)
                hx = [p[0] for p in head if p[1] <= cut]
                heads.setdefault(who, {}).setdefault(name, []).append(max(hx) - min(hx) + 1)
                head_centres.append((sum(p[0] for p in head) / len(head), sum(p[1] for p in head) / len(head)))
    if a.get("loop") and len(centres) > 1:
        # People: the head should stay steady (arms and legs swing). Others: the whole body.
        track = head_centres if len(head_centres) == len(centres) else centres
        jump = max(((track[i][0] - track[i - 1][0]) ** 2 + (track[i][1] - track[i - 1][1]) ** 2) ** 0.5 for i in range(len(track)))
        room = jump * ROOM_PER_SPRITE_PX
        part = "head" if track is head_centres else "body"
        (warns if room > 1.0 else []).append(f"{name}: {part} jumps {room:.1f} room px between frames in the loop")
        print(f"{name}: {part} moves at most {room:.1f} room px between loop frames")
    if centres and not name.startswith("blood"):
        cx = sum(c[0] for c in centres) / len(centres)
        cy = sum(c[1] for c in centres) / len(centres)
        off = ((cx - a["pivot"][0]) ** 2 + (cy - a["pivot"][1]) ** 2) ** 0.5 * ROOM_PER_SPRITE_PX
        if off > 3.0 and "death" not in name and "machete" not in name:
            warns.append(f"{name}: body centre is {off:.1f} room px from the turning point (pivot)")
    print(f"{name:16s} {a['frames']:2d}f  width {min(widths) * ROOM_PER_SPRITE_PX:.1f}-{max(widths) * ROOM_PER_SPRITE_PX:.1f} room px")

print("\nHead width (sprite px, median per sheet):")
for who, sheets in heads.items():
    med = {n: sorted(v)[len(v) // 2] for n, v in sheets.items()}
    base = med.get(f"{who}_walk") or med.get(f"{who}_idle")
    for n, m in med.items():
        print(f"  {n:16s} {m:3d}" + ("" if not base else f"  ({100 * m / base:.0f}% of walking)"))
        # Shading at the head's edge makes this rough: over 25% fails, 15-25% is for a look by eye.
        if base and "death" not in n and abs(m / base - 1) > 0.15:
            (fails if abs(m / base - 1) > 0.25 else warns).append(f"{n}: head is {100 * m / base:.0f}% the size of the walking head")

for who in ("hero", "enemy"):
    _, cells = frames(f"{who}_walk")
    w = max(max(p[0] for p in opaque(c)) - min(p[0] for p in opaque(c)) + 1 for c in cells) * ROOM_PER_SPRITE_PX
    print(f"\n{who}: up to {w:.1f} room px across = {w / PX_PER_M:.2f} m (person with swinging arms: 0.5-0.7 m)")
    if not 0.45 <= w / PX_PER_M <= 0.8:
        fails.append(f"{who}: {w / PX_PER_M:.2f} m across while walking")
_, cells = frames("dog_trot")
length = max(max(p[1] for p in opaque(c)) - min(p[1] for p in opaque(c)) + 1 for c in cells) * ROOM_PER_SPRITE_PX
print(f"dog: {length:.1f} room px long = {length / PX_PER_M:.2f} m (doberman 0.9-1.3 m)")
if not 0.9 <= length / PX_PER_M <= 1.3:
    fails.append(f"dog: {length / PX_PER_M:.2f} m long")

print()
for f in fails:
    print("FAIL  " + f)
for w in warns:
    print("WARN  " + w)
print(f"\n{len(fails)} failure(s), {len(warns)} warning(s)")
sys.exit(1 if fails else 0)
