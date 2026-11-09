"""QA: checks a pixel-art character set before it goes to Fianso.

    python3 tests/tools/check_pixel_sheets.py <folder with pixel_anims.json>
    python3 tests/tools/check_pixel_sheets.py <extras folder> <anims json name> <reference set folder>

With a reference set it also checks each new sheet against the original of the
same character (head width, body length, dead pose length) and that every
death ends on its *_dead picture.

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

ROOM_PER_SPRITE_PX = 1 / 3   # set B since 2026-10-23: every sheet draws at 1/3 room px per sprite px
PX_PER_M = 30.0            # room px per metre (person 0.5 m = 15 px)
folder = Path(sys.argv[1])
_data = json.loads((folder / (sys.argv[2] if len(sys.argv) > 2 else "pixel_anims.json")).read_text())
anims = {n: a for n, a in _data.get("anims", _data).items() if isinstance(a, dict) and "file" in a}
reference = Path(sys.argv[3]) if len(sys.argv) > 3 else None
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
        if edges and "footprint" not in name:   # footprint stamps are cut tight on purpose
            fails.append(f"{name} frame {i}: touches the cell edge ({', '.join(edges)}), may be cut off")
        lonely = [p for p in pts if not any((p[0] + dx, p[1] + dy) in pts for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)]
        if lonely:
            warns.append(f"{name} frame {i}: {len(lonely)} lonely pixel(s) at {lonely[:4]}")
        centres.append((sum(xs) / len(xs), sum(ys) / len(ys)))
        widths.append(max(xs) - min(xs) + 1)
        if who in ("hero", "enemy") and "blood" not in name and "footprint" not in name:
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
    if "death" in name and not a.get("dead") and (folder / f"{who}_dead.png").exists():
        a["dead"] = f"{who}_dead.png"
    if a.get("dead") and cells:
        dead = Image.open(folder / a["dead"]).convert("RGBA")
        last, still = cells[-1].crop(cells[-1].getbbox()), dead.crop(dead.getbbox())
        if last.size != still.size:
            fails.append(f"{name}: last frame {last.size} is not the dead pose {a['dead']} {still.size}")
        else:
            differ = sum(1 for p, q in zip(last.get_flattened_data(), still.get_flattened_data()) if p != q)
            if differ > 0.02 * last.size[0] * last.size[1]:
                fails.append(f"{name}: last frame differs from {a['dead']} in {differ} pixels")
    if centres and not name.startswith("blood") and not name.startswith("footprint"):
        cx = sum(c[0] for c in centres) / len(centres)
        cy = sum(c[1] for c in centres) / len(centres)
        off = ((cx - a["pivot"][0]) ** 2 + (cy - a["pivot"][1]) ** 2) ** 0.5 * ROOM_PER_SPRITE_PX
        if off > 3.0 and "death" not in name and "machete" not in name and "bite" not in name:
            warns.append(f"{name}: body centre is {off:.1f} room px from the turning point (pivot)")
    print(f"{name:16s} {a['frames']:2d}f  width {min(widths) * ROOM_PER_SPRITE_PX:.1f}-{max(widths) * ROOM_PER_SPRITE_PX:.1f} room px")

print("\nHead width (sprite px, median per sheet):")
for who, sheets in heads.items():
    med = {n: sorted(v)[len(v) // 2] for n, v in sheets.items()}
    base = med.get(f"{who}_walk") or med.get(f"{who}_idle")
    for n, m in med.items():
        print(f"  {n:16s} {m:3d}" + ("" if not base else f"  ({100 * m / base:.0f}% of walking)"))
        # Shading at the head's edge makes this rough: over 25% fails, 15-25% is for a look by eye.
        if base and "death" in n and not 0.7 <= m / base <= 1.1:
            warns.append(f"{n}: head is {100 * m / base:.0f}% the size of the walking head (corpses may be a little smaller, not much)")
        if base and "death" not in n and abs(m / base - 1) > 0.15:
            (fails if abs(m / base - 1) > 0.25 else warns).append(f"{n}: head is {100 * m / base:.0f}% the size of the walking head")

def trimmed_length(im):
    box = im.getbbox()
    return max(box[2] - box[0], box[3] - box[1]) * ROOM_PER_SPRITE_PX if box else 0.0


if reference:
    ref = json.loads((reference / "pixel_anims.json").read_text())["anims"]
    print("\nAgainst the original set:")
    for name, a in sorted(anims.items()):
        who = name.split("_")[0]
        if a.get("dead") and (reference / f"{who}_dead.png").exists():
            new = trimmed_length(Image.open(folder / a["dead"]).convert("RGBA"))
            old = trimmed_length(Image.open(reference / f"{who}_dead.png").convert("RGBA"))
            print(f"  {a['dead']:16s} {new:.1f} room px long vs {who}_dead.png {old:.1f} ({new / PX_PER_M:.2f} m)")
            if abs(new / old - 1) > 0.2:   # other poses (curled, arms up) differ on purpose: look by eye
                warns.append(f"{a['dead']}: {new:.1f} room px long, the original dead pose is {old:.1f} (more than 20% off; fine if the pose explains it)")
        base = f"{who}_trot" if who == "dog" else f"{who}_walk"
        if base in ref and "footprint" not in name and "death" not in name:
            sheet = Image.open(folder / a["file"]).convert("RGBA")
            rs = Image.open(reference / ref[base]["file"]).convert("RGBA")
            rc = rs.crop((0, 0, ref[base]["cell_w"], ref[base]["cell_h"])).getbbox()
            nb = sheet.crop((0, 0, a["cell_w"], a["cell_h"])).getbbox()
            ow, nw = rc[2] - rc[0], nb[2] - nb[0]
            print(f"  {name:16s} first frame {nw * ROOM_PER_SPRITE_PX:.1f} room px wide vs {base} {ow * ROOM_PER_SPRITE_PX:.1f}")
            if abs(nw / ow - 1) > 0.25:
                warns.append(f"{name}: first frame is {100 * nw / ow:.0f}% as wide as {base}")
    for who, sheets in heads.items():
        rname = f"{who}_dead.png"
        if (reference / rname).exists():
            im = Image.open(reference / rname).convert("RGBA")
            px = im.load()
            head = biggest_blob([p for p in opaque(im) if is_head(who, px[p])])
            if head:
                rw = max(p[0] for p in head) - min(p[0] for p in head) + 1
                for n, v in sheets.items():
                    m = sorted(v)[len(v) // 2]
                    print(f"  {n:16s} head {m} px vs {rname} head {rw} px")
                    if abs(m / rw - 1) > 0.25:
                        warns.append(f"{n}: head {m} px wide vs {rw} px in {rname}")

for who in ("hero", "enemy"):
    if f"{who}_walk" not in anims:
        continue
    _, cells = frames(f"{who}_walk")
    w = max(max(p[0] for p in opaque(c)) - min(p[0] for p in opaque(c)) + 1 for c in cells) * ROOM_PER_SPRITE_PX
    print(f"\n{who}: up to {w:.1f} room px across = {w / PX_PER_M:.2f} m (person with swinging arms: 0.5-0.7 m)")
    if not 0.45 <= w / PX_PER_M <= 0.8:
        fails.append(f"{who}: {w / PX_PER_M:.2f} m across while walking")
if "dog_trot" in anims:
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
