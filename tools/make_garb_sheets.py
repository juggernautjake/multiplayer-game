"""Draw the wizard garb into Pip's sprite sheets (v0.8.1), frame by frame, so it lines up with every animation.

    python tools/make_garb_sheets.py

Reads assets/pip/pip-spritesheet.png and pip-weapons.png (and their .json layouts) and writes, in assets/pip/garb/:
  <sheet>-wizard.png  the staff's look: a long grey robe to the ankles, a grey cloak behind, and a tall, soft, pointed
                      grey hat with a brim, its tip bent back (also used when he carries both the staff and the wand);
  <sheet>-shadow.png  the wand's look: a dark floor-length robe and a deep hood over his head, his face in its shadow;
  pip-hands.json      where his hands are in every frame of both sheets (for the weapon he carries: scripts/avatar.gd).
and assets/pip/carry/<weapon>.png (+ "-m" mirrored), small sprites of each weapon as he carries it, with carry.json
giving the pixel each is held by (and the staff's orb).

How each frame is drawn (64 x 64 cells, the same style: dark outline, flat shading):
  - the robe is one solid garment painted over him from the shoulders to the floor: its shape is his torso and legs
    in this frame, smoothed and widening toward the hem; inside it his clothes are painted over in three tones (light,
    mid, shadow side) with folds beside his legs, so it swings with his stride; his hands stay in front; the hem
    stops just above his soles; his arms' sleeves take the robe's colours; a rope belt (wizard);
  - the hat (wizard): a brim across his forehead and a crown rising 14 px to a tip that bends back (the way he's facing
    decides which way is back), shaded light on one side;
  - the cloak (wizard): a darker grey panel down each side of the robe, and the whole back seen from behind;
  - the hood (shadow): his hair and a 2 px rim round his head become hood, and the top of his face darkens into its
    shadow; seen from behind, the whole head is hood;
  - every new pixel next to empty space gets the dark outline.
"""
import colorsys
import json
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "pip")
OUT = os.path.join(ROOT, "garb")
CARRY = os.path.join(ROOT, "carry")
OUTLINE = (29, 22, 48)
CELL = 64

LOOKS = {
    "wizard": {"robe": [(150, 152, 158), (122, 124, 130), (98, 100, 107)], "cloak": [(104, 106, 112), (84, 86, 92)],
               "hat": [(146, 148, 154), (118, 120, 126), (92, 94, 100)], "band": (76, 70, 64), "rope": (176, 150, 104)},
    "shadow": {"robe": [(62, 52, 80), (46, 38, 62), (34, 28, 47)], "hood": [(84, 70, 108), (62, 51, 82), (112, 96, 140)]},
}
BACK_SIGN = {"S": 1, "SE": -1, "E": -1, "NE": -1, "N": 1}   # which way (in x) is "behind him" in each view


def hsv(c):
    return colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)


def classify(c):
    h, s, v = hsv(c)
    hd = h * 360
    if v < 0.28:
        return "outline"
    if 240 <= hd <= 275 and s > 0.15:
        return "scarf"
    if 40 <= hd <= 75 and s < 0.35 and v < 0.66:
        return "trousers"
    if 30 <= hd <= 50 and 0.2 <= s <= 0.62 and v > 0.58:
        return "tunic"
    if 10 <= hd < 30 and s > 0.5 and v < 0.82:
        return "hair"
    if (10 <= hd <= 32 and 0.15 <= s <= 0.5 and v > 0.8):
        return "skin"
    if (hd < 10 or hd > 340) and 0.2 <= s <= 0.4 and v < 0.45:
        return "boots"
    return "other"


def classify_cell(a):
    """classify() for a whole 64x64 cell at once (numpy)."""
    rgb = a[:, :, :3].astype(np.float32) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    v = mx
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    hd = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m, (mx - r) / np.maximum(d, 1e-6), 0)
    gc = np.where(m, (mx - g) / np.maximum(d, 1e-6), 0)
    bc = np.where(m, (mx - b) / np.maximum(d, 1e-6), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
    hd = np.where(m, (h / 6.0) % 1.0 * 360.0, 0.0)
    out = np.full(mx.shape, "other", dtype=object)
    conds = [
        (v < 0.28, "outline"),
        ((hd >= 240) & (hd <= 275) & (s > 0.15), "scarf"),
        ((hd >= 40) & (hd <= 75) & (s < 0.35) & (v < 0.66), "trousers"),
        ((hd >= 30) & (hd <= 50) & (s >= 0.2) & (s <= 0.62) & (v > 0.58), "tunic"),
        ((hd >= 10) & (hd < 30) & (s > 0.5) & (v < 0.82), "hair"),
        ((hd >= 10) & (hd <= 32) & (s >= 0.15) & (s <= 0.5) & (v > 0.8), "skin"),
        (((hd < 10) | (hd > 340)) & (s >= 0.2) & (s <= 0.4) & (v < 0.45), "boots"),
    ]
    done = np.zeros(mx.shape, bool)
    for c, name in conds:
        sel = c & ~done
        out[sel] = name
        done |= sel
    out[a[:, :, 3] == 0] = ""
    return out


def shade(palette, v):
    """Pick a palette shade (light, mid, dark) from a source pixel's brightness."""
    return palette[0] if v > 0.8 else (palette[1] if v > 0.6 else palette[2])


def put(a, y, x, c):
    if 0 <= y < CELL and 0 <= x < CELL:
        a[y, x, :3] = c
        a[y, x, 3] = 255


def outline_new(a, new):
    """Every new pixel that touches empty space becomes outline."""
    op = a[:, :, 3] > 0
    for y, x in zip(*np.nonzero(new)):
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if not (0 <= yy < CELL and 0 <= xx < CELL) or not op[yy, xx]:
                a[y, x, :3] = OUTLINE
                break


def cell_info(cls, a):
    op = a[:, :, 3] > 0
    rows = [y for y in range(CELL) if op[y].sum() >= 5]
    if not rows:
        return None
    top, bottom = rows[0], max(y for y in range(CELL) if op[y].any())
    scarf = [y for y in range(CELL) if (cls[y] == "scarf").any()]
    neck = scarf[0] if scarf else top + 20
    return top, bottom, neck


def draw_frame(a, look, view, is_weapons):
    """Draw one 64x64 RGBA cell (modified in place)."""
    cls = classify_cell(a)
    info = cell_info(cls, a)
    if info is None:
        return
    top, bottom, neck = info
    pal = LOOKS[look]
    lying = bottom - top < 30            # lying down: robe colours only
    # 1. clothing recoloured to the robe
    for y in range(CELL):
        for x in range(CELL):
            k = cls[y, x]
            if k in ("tunic", "trousers", "scarf"):
                v = hsv(tuple(int(t) for t in a[y, x, :3]))[2]
                a[y, x, :3] = shade(pal["robe"], v + (0.1 if k == "scarf" else 0.0) - (0.1 if k == "trousers" else 0.0))
    if lying:
        return
    # 2. the robe: one solid garment from the shoulders to the floor, painted over his body. Its shape comes from his
    # torso and legs in this frame (their span in each row, smoothed over a few rows), widening toward the hem; inside
    # it, his clothes and the lines between them are painted over in the robe's three tones (light on the left, the
    # shadow side on the right, darker folds running down from where his legs are, so they follow the stride); only
    # his hands and anything that isn't him (a weapon) stay. The hem stops just above the soles: the boot tips peek out.
    core = np.isin(cls, ["tunic", "trousers", "boots", "scarf"])
    hem = bottom - 1
    spans = {}
    for y in range(neck, hem + 1):
        xs = np.nonzero(core[y])[0]
        if len(xs):
            spans[y] = (xs.min(), xs.max())
    if not spans:
        return
    robe = np.zeros((CELL, CELL), bool)
    legs = cls == "trousers"
    rows = sorted(spans)
    for y in range(rows[0], hem + 1):
        near = [spans[q] for q in range(y - 2, y + 3) if q in spans]
        if not near:
            continue
        x0 = min(n[0] for n in near)
        x1 = max(n[1] for n in near)
        u = (y - rows[0]) / max(hem - rows[0], 1)
        flare = int(round(u * u * 3.0))
        x0 -= flare
        x1 += flare
        leg_cols = set(np.nonzero(legs[max(y - 3, 0):y + 1].any(axis=0))[0].tolist())
        for x in range(max(x0, 0), min(x1, CELL - 1) + 1):
            k = cls[y, x]
            if k in ("skin", "other", "hair") and a[y, x, 3] > 0 and y < hem - 1:
                continue   # his hands (and any weapon) stay in front of the robe
            t = (x - x0) / max(x1 - x0, 1)
            col = pal["robe"][0] if t < 0.35 else (pal["robe"][1] if t < 0.75 else pal["robe"][2])
            if u > 0.25 and (x - 1) in leg_cols and x not in leg_cols:
                col = pal["robe"][2]   # a fold beside each leg
            if look == "wizard":   # the cloak: a darker panel down each side (and the whole back, seen from behind)
                if view in ("N", "NE") and 0.15 < t < 0.85:
                    col = pal["cloak"][0] if t < 0.5 else pal["cloak"][1]
                elif t < 0.12 or t > 0.88:
                    col = pal["cloak"][1]
            put(a, y, x, col)
            robe[y, x] = True
    # sleeves: the rest of his tunic (his arms) in the robe's colours, by their light and shade
    for y in range(CELL):
        for x in range(CELL):
            if not robe[y, x] and cls[y, x] in ("tunic", "scarf", "trousers"):
                v = hsv(tuple(int(t) for t in a[y, x, :3]))[2]
                a[y, x, :3] = shade(pal["robe"], v)
    # sleeves down the arms: his bare arms below the shoulders become sleeve, all but the hands (the last 4 rows of
    # each arm's skin)
    skin = (cls == "skin")
    skin[:neck + 1] = False
    seen = np.zeros((CELL, CELL), bool)
    for sy, sx in zip(*np.nonzero(skin)):
        if seen[sy, sx]:
            continue
        comp = []
        stack = [(sy, sx)]
        seen[sy, sx] = True
        while stack:
            y, x = stack.pop()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < CELL and 0 <= xx < CELL and skin[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    stack.append((yy, xx))
        lo = max(c[0] for c in comp)
        hi = min(c[0] for c in comp)
        if lo - hi < 5:
            continue   # just a hand
        for y, x in comp:
            if y < lo - 3:
                a[y, x, :3] = pal["robe"][1]
    # a rope belt (wizard) at the waist, inside the robe
    if look == "wizard":
        waist = min(rows[0] + 9, hem - 4)
        for x in np.nonzero(robe[waist])[0]:
            a[waist, x, :3] = pal["rope"]
    # the outline on the robe's new silhouette
    edge = np.zeros((CELL, CELL), bool)
    for y, x in zip(*np.nonzero(robe)):
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if not (0 <= yy < CELL and 0 <= xx < CELL) or a[yy, xx, 3] == 0:
                edge[y, x] = True
                break
    for y, x in zip(*np.nonzero(edge)):
        a[y, x, :3] = OUTLINE
    before = a[:, :, 3] > 0
    # 4. head wear
    head_rows = range(max(top - 1, 0), neck)
    head_xs = np.nonzero(before[top:neck].any(axis=0))[0]
    if len(head_xs) == 0:
        return
    hx0, hx1 = head_xs.min(), head_xs.max()
    back = BACK_SIGN.get(view, 1)
    if look == "wizard":
        new = np.zeros((CELL, CELL), bool)
        base = top + 4
        # the brim, across the forehead, two pixels deep
        for y in (base, base + 1):
            for x in range(hx0 - 3, hx1 + 4):
                put(a, y, x, pal["hat"][1] if y == base else pal["hat"][2])
                new[y, x] = True
        # the crown: from the head's width up 14 px, its top bending back
        width = hx1 - hx0 - 2
        cx = (hx0 + hx1) / 2.0
        for i in range(1, 18):
            y = base - i
            u = i / 17.0
            half = max(width / 2.0 * (1 - u) ** 0.9, 0.6)
            c = cx + back * 5.0 * u ** 2.2
            for x in range(int(round(c - half)), int(round(c + half)) + 1):
                if y < 0:
                    continue
                col = pal["hat"][0] if x < c - half * 0.2 else pal["hat"][1]
                if i == 1:
                    col = pal["band"]
                put(a, y, x, col)
                new[y, x] = True
        # clear the hair that pokes above the brim but outside the crown (it's under the hat now)
        for y in range(0, base):
            for x in range(CELL):
                if before[y, x] and not new[y, x] and cls[y, x] in ("hair", "outline"):
                    a[y, x, 3] = 0
        outline_new(a, new)
    else:
        # the hood: a smooth rounded cowl over his head and hair (not following his spiky hair), from just above his
        # head down onto his shoulders, his face shows in the opening, in its shadow;
        # seen from behind, it is all hood
        new = np.zeros((CELL, CELL), bool)
        hood = pal["hood"]
        facing_away = view == "N"
        skin_rows = [y for y in range(top, neck) if (cls[y] == "skin").any()]
        cx = (hx0 + hx1) / 2.0
        cy = (top - 2 + neck + 2) / 2.0
        rx = (hx1 - hx0) / 2.0 + 1.5
        ry = (neck + 2 - (top - 2)) / 2.0
        for y in range(max(top - 3, 0), min(neck + 3, CELL)):
            for x in range(CELL):
                inside = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0
                if not inside:
                    continue
                k = cls[y, x] if a[y, x, 3] > 0 else ""
                face = k == "skin" and not facing_away and y >= top + 3
                if face:
                    if y < top + 9:
                        a[y, x, :3] = (a[y, x, :3] * 0.62).astype(np.uint8)   # in the hood's shadow
                    continue
                if k in ("other",) and y > top + 4 and not facing_away:
                    continue   # eyes, mouth
                put(a, y, x, hood[0] if x < cx - rx * 0.2 else hood[1])
                new[y, x] = True
        # hair spikes poking out above the hood are under it now
        for y in range(0, int(cy)):
            for x in range(CELL):
                if a[y, x, 3] > 0 and not new[y, x] and cls[y, x] in ("hair", "outline") and ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 > 1.0:
                    a[y, x, 3] = 0
        # a highlight along the top
        for x in range(int(cx - rx), int(cx + rx) + 1):
            ys = [y for y in range(0, neck) if 0 <= x < CELL and new[y, x]]
            if len(ys) > 2:
                a[ys[1], x, :3] = hood[2]
        outline_new(a, new)


def hands(a, view):
    """The skin-coloured clusters below the neck: [left x, left y, right x, right y] on screen (or -1)."""
    info_cls = classify_cell(a)
    inf = cell_info(info_cls, a)
    if inf is None:
        return [-1, -1, -1, -1]
    top, bottom, neck = inf
    pts = [(x, y) for y in range(neck + 2, bottom - 2) for x in range(CELL) if info_cls[y, x] == "skin"]
    if not pts:
        return [-1, -1, -1, -1]
    xs = sorted(p[0] for p in pts)
    mid = (xs[0] + xs[-1]) / 2.0
    left = [p for p in pts if p[0] <= mid] or pts
    right = [p for p in pts if p[0] > mid] or pts
    cl = (int(round(sum(p[0] for p in left) / len(left))), int(round(sum(p[1] for p in left) / len(left))))
    cr = (int(round(sum(p[0] for p in right) / len(right))), int(round(sum(p[1] for p in right) / len(right))))
    return [cl[0], cl[1], cr[0], cr[1]]


def make(sheet):
    meta = json.load(open(os.path.join(ROOT, sheet + ".json")))
    src = np.array(Image.open(os.path.join(ROOT, sheet + ".png")).convert("RGBA"))
    view_of = {}
    frames_of = {}
    for an in meta["animations"]:
        view_of[int(an["row"])] = an["dir"]
        frames_of[int(an["row"])] = int(an["frames"])
    hand_map = {}
    for look in LOOKS:
        out = src.copy()
        for row, view in view_of.items():
            for f in range(frames_of[row]):
                y0, x0 = row * CELL, f * CELL
                cellv = out[y0:y0 + CELL, x0:x0 + CELL].copy()
                if look == "wizard":
                    hand_map["%d:%d" % (row, f)] = hands(src[y0:y0 + CELL, x0:x0 + CELL].copy(), view)
                draw_frame(cellv, look, view, sheet == "pip-weapons")
                out[y0:y0 + CELL, x0:x0 + CELL] = cellv
        os.makedirs(OUT, exist_ok=True)
        Image.fromarray(out).save(os.path.join(OUT, "%s-%s.png" % (sheet, look)))
        print("wrote garb/%s-%s.png" % (sheet, look))
    return hand_map


# ---------------------------------------------------------------- the weapons he carries
WOOD = (143, 96, 56)
WOOD_D = (104, 68, 40)
STEEL = (206, 214, 224)
STEEL_D = (140, 150, 166)
GOLD = (222, 180, 74)
ORB = (150, 220, 255)
ORB_L = (230, 248, 255)
VIOLET = (200, 140, 255)


def sprite(w, h, pixels, grip, extra=None):
    a = np.zeros((h, w, 4), np.uint8)
    for (x, y), c in pixels.items():
        a[y, x, :3] = c
        a[y, x, 3] = 255
    shape = a[:, :, 3] > 0
    o = a.copy()
    for y in range(h):
        for x in range(w):
            if not shape[y, x] and any(0 <= y + dy < h and 0 <= x + dx < w and shape[y + dy, x + dx] for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                o[y, x, :3] = OUTLINE
                o[y, x, 3] = 255
    return o, {"grip": list(grip), **(extra or {})}


def line(px, x0, y0, x1, y1, c, thick=1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        x = round(x0 + (x1 - x0) * i / n)
        y = round(y0 + (y1 - y0) * i / n)
        for t in range(thick):
            px[(x + t, y)] = c


def weapons():
    os.makedirs(CARRY, exist_ok=True)
    meta = {}
    W = {}
    # sword: held low at his side, the blade pointing down and a little forward
    px = {}
    line(px, 4, 3, 4, 6, WOOD_D)                 # grip
    line(px, 2, 7, 7, 7, GOLD)                   # cross-guard
    line(px, 4, 8, 7, 24, STEEL, 2)              # blade
    line(px, 5, 8, 8, 24, STEEL_D)
    W["sword"] = sprite(12, 27, px, (4, 4))
    # club: hanging at his side, the heavy end down
    px = {}
    line(px, 4, 2, 5, 12, WOOD, 2)
    for y in range(12, 19):
        for x in range(3, 9):
            px[(x, y)] = WOOD if x < 7 else WOOD_D
    W["club"] = sprite(12, 21, px, (4, 4))
    # bow: upright in the hand, the string on the inside
    px = {}
    for y in range(1, 24):
        u = (y - 12) / 11.0
        x = int(round(5 - 3 * (1 - u * u)))
        px[(x, y)] = WOOD
        px[(x + 1, y)] = WOOD_D
        px[(7, y)] = (232, 228, 214)
    W["bow"] = sprite(10, 25, px, (3, 12))
    # slingshot: the fork up out of his fist
    px = {}
    line(px, 4, 6, 4, 10, WOOD, 2)
    line(px, 2, 1, 4, 6, WOOD)
    line(px, 7, 1, 5, 6, WOOD)
    line(px, 2, 1, 7, 1, (120, 80, 60))
    W["sling"] = sprite(10, 12, px, (4, 9))
    # staff: tall, upright like a walking staff, an orb in a little cage at the top
    px = {}
    line(px, 4, 9, 4, 43, WOOD_D, 2)
    for x in range(2, 8):
        px[(x, 8)] = WOOD
    line(px, 2, 7, 2, 3, WOOD)
    line(px, 7, 7, 7, 3, WOOD)
    for y in range(2, 8):
        for x in range(3, 7):
            px[(x, y)] = ORB_L if (x == 4 and y == 3) else ORB
    W["staff"] = sprite(10, 46, px, (4, 26), {"orb": [4, 4]})
    # wand: short, pointing down and forward, a violet tip
    px = {}
    line(px, 2, 2, 8, 10, (60, 44, 40), 2)
    px[(9, 11)] = VIOLET
    px[(8, 11)] = VIOLET
    px[(9, 10)] = (240, 220, 255)
    W["wand"] = sprite(12, 13, px, (3, 3), {"orb": [9, 11]})
    for name, (img, m) in W.items():
        Image.fromarray(img).save(os.path.join(CARRY, name + ".png"))
        Image.fromarray(img[:, ::-1].copy()).save(os.path.join(CARRY, name + "-m.png"))
        m["size"] = [img.shape[1], img.shape[0]]
        meta[name] = m
    json.dump(meta, open(os.path.join(CARRY, "carry.json"), "w"), indent=1)
    print("wrote carry/*.png and carry.json")


if __name__ == "__main__":
    out = {}
    for sheet in ["pip-spritesheet", "pip-weapons"]:
        out[sheet] = make(sheet)
    json.dump(out, open(os.path.join(OUT, "pip-hands.json"), "w"))
    print("wrote garb/pip-hands.json")
    weapons()
