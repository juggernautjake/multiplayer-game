"""Pip's costumes (v0.9.0): one per weapon, painted over him in every frame of both sheets, like real clothing.

    python tools/make_costumes.py          (tools/make_garb_sheets.py runs it too)

For each look writes assets/pip/garb/<sheet>-<look>.png and <sheet>-<look>-accent.png, for both pip-spritesheet and
pip-weapons, frame for frame with the originals:
  brawler  (fists)     a sleeveless leather vest, hand wraps, a sash and a headband (accent: headband and sash)
  knight   (sword)     a mail shirt, a tabard front and back with an emblem, shoulder guards, a mail coif (accent: tabard)
  barbarian (club)     bare chest, a fur mantle, a leather harness, a hide kilt, fur-topped boots (accent: kilt belt)
  ranger   (bow)       a leather jerkin, a green-brown cloak, the hood down round the neck, bracers, a quiver on the back
                       (accent: the scarf in the hood)
  scout    (slingshot) a short vest over a white shirt with rolled sleeves, a satchel on the hip, a bandana (accent)
  wizard   (staff)     a long grey robe, a grey cloak, a rope belt, a tall soft hat (accent: the hat band)
  shadow   (wand)      a heavy floor-length robe in a four-tone violet-black ramp with a cool highlight, a deep peaked
                       cowl hood framing the face (lighter rim, face in shadow, a seam down the back, a cape collar on
                       the shoulders), wide sleeves with the hands out (accent: the trim down the front, the hood's rim
                       and the cuffs)
The accent sheet holds only the accent pixels, as grey shades: the game draws it over Pip tinted with the player's
colour, so players in the same costume can tell each other apart (scripts/avatar.gd).

Each frame is read first (tools/make_garb_sheets.py's classifier): head (from the first wide row to the neck: the
scarf), torso and legs (his tunic and trousers), boots, his arms (the skin below the neck: the last rows of each arm are
the hand). Garments are then painted over those regions in 3-4 tone ramps lit from the upper left, and every pixel of a
garment that touches empty space gets Pip's dark outline.
"""
import json
import os
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_garb_sheets import classify_cell, CELL, OUTLINE, BACK_SIGN   # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "pip")
OUT = os.path.join(ROOT, "garb")
GREY = [(235, 235, 235), (196, 196, 196), (150, 150, 150), (112, 112, 112)]   # accent shades (tinted in the game)

P = {
    "leather": [(150, 104, 66), (121, 82, 52), (93, 62, 40)],
    "dark_leather": [(104, 72, 50), (82, 56, 40), (62, 42, 30)],
    "skin": [(245, 188, 147), (217, 141, 116), (190, 118, 98)],
    "wrap": [(240, 234, 220), (206, 198, 182), (168, 160, 146)],
    "mail": [(178, 184, 194), (140, 146, 158), (104, 110, 122)],
    "steel": [(206, 212, 222), (160, 168, 180), (120, 128, 140)],
    "fur": [(170, 128, 86), (136, 98, 64), (102, 72, 46)],
    "hide": [(196, 160, 112), (166, 130, 88), (132, 100, 66)],
    "green": [(98, 120, 72), (76, 96, 56), (58, 74, 44)],
    "cloak_green": [(90, 100, 66), (70, 78, 52), (54, 60, 40)],
    "ochre": [(196, 150, 72), (164, 122, 56), (128, 94, 44)],
    "shirt": [(238, 234, 222), (206, 200, 186), (170, 164, 150)],
    "trousers_dark": [(92, 80, 70), (74, 64, 56), (58, 50, 44)],
    "grey_robe": [(150, 152, 158), (122, 124, 130), (98, 100, 107)],
    "grey_cloak": [(104, 106, 112), (84, 86, 92)],
    "hat": [(146, 148, 154), (118, 120, 126), (92, 94, 100)],
    "rope": [(196, 168, 116), (168, 140, 92), (136, 110, 70)],
    "gold": [(240, 206, 96), (206, 168, 64), (160, 124, 40)],
    "night": [(86, 76, 112), (60, 52, 80), (43, 37, 59), (31, 26, 43)],   # the dark robe: cool highlight, light, mid, dark
}


class Frame:
    """One 64x64 cell and what's where in it."""

    def __init__(self, a, view):
        self.a = a
        self.view = view
        self.acc = np.zeros((CELL, CELL, 4), np.uint8)
        self.cls = classify_cell(a)
        op = a[:, :, 3] > 0
        rows = [y for y in range(CELL) if op[y].sum() >= 5]
        self.ok = bool(rows)
        if not self.ok:
            return
        self.top = rows[0]
        self.bottom = max(y for y in range(CELL) if op[y].any())
        scarf = [y for y in range(CELL) if (self.cls[y] == "scarf").any()]
        self.neck = scarf[0] if scarf else self.top + 20
        self.lying = self.bottom - self.top < 30
        hx = np.nonzero(op[self.top:self.neck].any(axis=0))[0]
        self.hx0, self.hx1 = (hx.min(), hx.max()) if len(hx) else (24, 40)
        self.cx = (self.hx0 + self.hx1) / 2.0
        self.back = BACK_SIGN.get(view, 1)
        core = np.isin(self.cls, ["tunic", "trousers", "boots", "scarf"])
        self.spans = {}
        for y in range(self.neck, self.bottom + 1):
            xs = np.nonzero(core[y])[0]
            if len(xs):
                self.spans[y] = (int(xs.min()), int(xs.max()))
        self.waist = min(self.neck + 9, self.bottom - 6)
        self.knee = self.bottom - 6
        boots = [y for y in range(CELL) if (self.cls[y] == "boots").any()]
        self.boot_top = boots[0] if boots else self.bottom - 2
        # the arms: skin below the neck, in connected pieces; each piece's last 3 rows are the hand
        skin = self.cls == "skin"
        skin[:self.neck + 1] = False
        seen = np.zeros((CELL, CELL), bool)
        self.arms = []
        for sy, sx in zip(*np.nonzero(skin)):
            if seen[sy, sx]:
                continue
            comp, stack = [], [(sy, sx)]
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
            hand = [c for c in comp if c[0] >= lo - 2]
            arm = [c for c in comp if c[0] < lo - 2]
            self.arms.append((arm, hand))
        self.new = np.zeros((CELL, CELL), bool)

    def span(self, y, pad=0):
        near = [self.spans[q] for q in range(y - 2, y + 3) if q in self.spans]
        if not near:
            return None
        return min(n[0] for n in near) - pad, max(n[1] for n in near) + pad

    def put(self, y, x, col, accent=None):
        if not (0 <= y < CELL and 0 <= x < CELL):
            return
        if self.a[y, x, 3] == 0:
            self.new[y, x] = True
        self.a[y, x, :3] = col
        self.a[y, x, 3] = 255
        if accent is not None:
            self.acc[y, x, :3] = accent
            self.acc[y, x, 3] = 255
        else:
            self.acc[y, x, 3] = 0

    def tone(self, pal, x, x0, x1, y=None, y0=None, y1=None):
        """Lit from the upper left: the light tone on the left third, the dark on the right (and low down)."""
        t = (x - x0) / max(x1 - x0, 1)
        if y is not None and y1 is not None:
            t = t * 0.8 + 0.2 * (y - y0) / max(y1 - y0, 1)
        n = len(pal)
        return pal[min(int(t * n), n - 1)]

    def recolor(self, classes, pal, rows=None, accent=False):
        for y in range(CELL) if rows is None else rows:
            for x in range(CELL):
                if self.a[y, x, 3] > 0 and self.cls[y, x] in classes:
                    v = max(self.a[y, x, :3]) / 255.0
                    i = 0 if v > 0.8 else (1 if v > 0.62 else 2)
                    i = min(i, len(pal) - 1)
                    self.put(y, x, pal[i], GREY[i] if accent else None)

    def outline(self):
        for y, x in zip(*np.nonzero(self.new)):
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if not (0 <= yy < CELL and 0 <= xx < CELL) or self.a[yy, xx, 3] == 0:
                    self.a[y, x, :3] = OUTLINE
                    self.acc[y, x, 3] = 0
                    break
        self.new[:] = False


# ================================================================ garments
def fill_body(fr, y0, y1, pal, flare=3, folds=True, keep_hands=True, accent_rows=None, cols_fn=None):
    """A solid garment over his torso and legs from row y0 to y1, widening by `flare` px toward y1."""
    legs = fr.cls == "trousers"
    for y in range(y0, y1 + 1):
        sp = fr.span(y)
        if sp is None:
            continue
        u = (y - y0) / max(y1 - y0, 1)
        f = int(round(u * u * flare))
        x0, x1 = sp[0] - f, sp[1] + f
        leg_cols = set(np.nonzero(legs[max(y - 3, 0):y + 1].any(axis=0))[0].tolist())
        for x in range(max(x0, 0), min(x1, CELL - 1) + 1):
            k = fr.cls[y, x]
            if keep_hands and k in ("skin", "other", "hair") and fr.a[y, x, 3] > 0 and y < fr.bottom - 1:
                continue
            col = fr.tone(pal, x, x0, x1)
            if folds and u > 0.2 and (x - 1) in leg_cols and x not in leg_cols:
                col = pal[-1]
            acc = None
            if cols_fn:
                r = cols_fn(y, x, x0, x1, u)
                if r is not None:
                    col, acc = r
            fr.put(y, x, col, acc)


def sleeves(fr, pal, cuff=None, bare=False, wraps=None, bracer=None):
    """His arms: sleeves (or bare skin) down to the hands; an optional coloured cuff, hand wraps or bracers."""
    for arm, hand in fr.arms:
        for (y, x) in arm:
            if bare:
                continue
            fr.put(y, x, pal[1] if (y + x) % 5 else pal[2])
        if arm and cuff is not None:
            lo = max(c[0] for c in arm)
            for (y, x) in arm:
                if y == lo:
                    fr.put(y, x, cuff[0], cuff[1])
        if arm and bracer is not None:
            lo = max(c[0] for c in arm)
            for (y, x) in arm:
                if y >= lo - 2:
                    fr.put(y, x, bracer[1] if y == lo - 1 else bracer[0])
        if wraps is not None:
            for (y, x) in hand:
                fr.put(y, x, wraps[0] if (y + x) % 3 else wraps[1])
    # the tunic's own sleeve pixels (outside his body's span) take the garment's colour, or skin if bare
    for y in range(fr.neck, fr.waist + 4):
        sp = fr.span(y)
        for x in range(CELL):
            if fr.cls[y, x] == "tunic" and sp is not None and (x < sp[0] or x > sp[1]):
                fr.put(y, x, (P["skin"][1] if bare else pal[1]))


def head_cap(fr, pal, rows, accent=None):
    """Paint over his hair from the top of his head down `rows` rows (a cap, a coif, a bandana)."""
    for y in range(max(fr.top - 1, 0), min(fr.top + rows, fr.neck)):
        for x in range(CELL):
            if fr.a[y, x, 3] > 0 and fr.cls[y, x] in ("hair", "outline") and fr.cls[y, x] != "skin":
                if fr.cls[y, x] == "outline" and y > fr.top + 1:
                    continue
                fr.put(y, x, fr.tone(pal, x, fr.hx0, fr.hx1), accent)


def band(fr, row, pal, accent=None, tail=0):
    """A band round the head at `row` (a headband), with tails out the back."""
    for x in range(fr.hx0, fr.hx1 + 1):
        if fr.a[row, x, 3] > 0 and fr.cls[row, x] != "outline":
            fr.put(row, x, pal[0], accent)
            fr.put(row + 1, x, pal[1], accent)
    if tail:
        x = fr.hx1 + 1 if fr.back > 0 else fr.hx0 - 1
        for i in range(tail):
            fr.put(row + 1 + i // 2, x + fr.back * i, pal[1], accent)
            fr.put(row + 2 + i // 2, x + fr.back * i, pal[2], accent)


def cloak_panels(fr, pal, y0, y1, back_full=True):
    """A cloak behind him: a panel down each side of his body, and his whole back when we see him from behind."""
    for y in range(y0, y1 + 1):
        sp = fr.span(y, 1)
        if sp is None:
            continue
        x0, x1 = sp[0] - 1, sp[1] + 1
        for x in range(max(x0, 0), min(x1, CELL - 1) + 1):
            t = (x - x0) / max(x1 - x0, 1)
            behind = fr.view in ("N", "NE") and back_full
            if behind and fr.cls[y, x] not in ("skin", "other"):
                fr.put(y, x, pal[0] if t < 0.5 else pal[1])
            elif (t < 0.1 or t > 0.9) and fr.a[y, x, 3] == 0:
                fr.put(y, x, pal[1])


def hat(fr):
    """The wizard's hat: a brim across his forehead, a crown rising 17 px to a tip bent back, the band in the accent."""
    base = fr.top + 4
    pal = P["hat"]
    mine = set()
    for y in (base, base + 1):
        for x in range(fr.hx0 - 3, fr.hx1 + 4):
            fr.put(y, x, pal[1] if y == base else pal[2])
            mine.add((y, x))
    width = fr.hx1 - fr.hx0 - 2
    for i in range(1, 18):
        y = base - i
        u = i / 17.0
        half = max(width / 2.0 * (1 - u) ** 0.9, 0.6)
        c = fr.cx + fr.back * 5.0 * u ** 2.2
        for x in range(int(round(c - half)), int(round(c + half)) + 1):
            if y < 0:
                continue
            if i in (1, 2):
                fr.put(y, x, GREY[i], GREY[i])
            else:
                fr.put(y, x, pal[0] if x < c - half * 0.2 else pal[1])
            mine.add((y, x))
    for y in range(0, base):   # his hair above the brim is under the hat
        for x in range(CELL):
            if (y, x) not in mine and fr.a[y, x, 3] > 0 and fr.cls[y, x] in ("hair", "outline"):
                fr.a[y, x, 3] = 0
                fr.acc[y, x, 3] = 0


def hood(fr, pal, trim):
    """The deep cowl: a full rounded hood over his head and hair, peaked at the top and leaning back, reaching down onto
    his shoulders as a cape collar. Facing us, his face shows in the opening, framed by a lighter rim, its upper part
    in the hood's shadow; from behind, a seam runs down its middle; side on, it reaches past the back of his head."""
    facing_us = fr.view in ("S", "SE")
    side = fr.view == "E"
    rx = (fr.hx1 - fr.hx0) / 2.0 + 2.0
    ry = (fr.neck + 1 - (fr.top - 3)) / 2.0
    cx = fr.cx + (fr.back * 1.5 if side else (fr.back * 0.5 if fr.view in ("SE", "NE") else 0.0))
    if side:
        rx += 1.0
    cy = (fr.top - 3 + fr.neck + 1) / 2.0
    # the face: on each row, everything between his cheeks (eyes and mouth included), not his hair
    face = np.zeros((CELL, CELL), bool)
    for y in range(fr.top + 3, fr.neck):
        xs = np.nonzero(fr.cls[y] == "skin")[0]
        if len(xs) >= 2:
            for x in range(int(xs.min()), int(xs.max()) + 1):
                if fr.cls[y, x] != "hair":
                    face[y, x] = True
    hood_px = np.zeros((CELL, CELL), bool)
    for y in range(max(fr.top - 4, 0), min(fr.neck + 2, CELL)):
        for x in range(CELL):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 > 1.0:
                continue
            if facing_us and face[y, x]:
                continue
            if side and face[y, x] and (x - fr.cx) * fr.back < 0:
                continue   # side on: his face shows at the front
            hood_px[y, x] = True
    # the peak: a soft point above, leaning back
    for i in range(1, 4):
        y = int(cy - ry) - i + 1
        c = cx + fr.back * (0.8 * i)
        half = 2.4 - 0.7 * i
        for x in range(int(round(c - half)), int(round(c + half)) + 1):
            if 0 <= y < CELL:
                hood_px[y, x] = True
    # the cape collar: down onto the shoulders, wider than the head, rounding off at the ends
    for y in range(fr.neck - 1, min(fr.neck + 5, CELL)):
        sp = fr.span(y, 0)
        if sp is None:
            continue
        ext = 2 - max(y - fr.neck - 1, 0) // 2
        for x in range(sp[0] - ext, sp[1] + ext + 1):
            if 0 <= x < CELL and fr.cls[y, x] != "skin" and not face[min(y, CELL - 1), x]:
                hood_px[y, x] = True
    # paint: lit from the upper left, four tones; the rim round the face opening in the accent; a seam at the back
    for y, x in zip(*np.nonzero(hood_px)):
        lx = (x - cx) / rx
        ly = (y - cy) / ry
        light = -0.6 * lx - 0.5 * ly
        i = 0 if light > 0.55 else (1 if light > 0.05 else (2 if light > -0.45 else 3))
        col = pal[i]
        acc = None
        if facing_us and any(0 <= y + dy < CELL and 0 <= x + dx < CELL and face[y + dy, x + dx] for dy, dx in ((1, 0), (0, 1), (0, -1))):
            col = pal[0]   # the rim round the opening (top and sides): the hood's light tone
        if fr.view in ("N", "NE") and abs(x - cx) < 0.6 and y < fr.neck:
            col = pal[3]   # the seam
        fr.put(y, x, col, acc)
    # the face in the hood's shadow: deepest at the edges and the brow
    if facing_us or side:
        for y, x in zip(*np.nonzero(face)):
            if fr.cls[y, x] != "skin":
                continue
            near = any(0 <= y + dy < CELL and 0 <= x + dx < CELL and hood_px[y + dy, x + dx]
                       for dy in (-2, -1, 0, 1, 2) for dx in (-2, -1, 0, 1, 2))
            k = 0.66 if near else (0.82 if y < fr.top + 9 else 0.95)
            fr.a[y, x, :3] = (fr.a[y, x, :3] * k).astype(np.uint8)
    # his hair is under the hood
    for y in range(0, fr.neck):
        for x in range(CELL):
            if fr.a[y, x, 3] > 0 and not hood_px[y, x] and fr.cls[y, x] in ("hair",):
                fr.put(y, x, pal[2])
            elif fr.a[y, x, 3] > 0 and not hood_px[y, x] and fr.cls[y, x] == "outline" and y < cy - ry + 1:
                fr.a[y, x, 3] = 0


# ================================================================ the costumes
def brawler(fr):
    fill_body(fr, fr.neck + 1, fr.waist, P["dark_leather"], flare=0, folds=False)          # the vest
    fill_body(fr, fr.waist + 2, fr.boot_top - 1, P["trousers_dark"], flare=0)              # trousers
    sleeves(fr, P["skin"], bare=True, wraps=(P["wrap"][0], P["wrap"][1]))
    for y in (fr.waist, fr.waist + 1):                                                      # the sash
        sp = fr.span(y)
        if sp:
            for x in range(sp[0], sp[1] + 1):
                fr.put(y, x, GREY[1] if y == fr.waist else GREY[2], GREY[1] if y == fr.waist else GREY[2])
            x = sp[1] + 1 if fr.back > 0 else sp[0] - 1
            for i in range(3):
                fr.put(fr.waist + 1 + i, x, GREY[2], GREY[2])
    band(fr, fr.top + 6, GREY, accent=GREY[1], tail=4)


def knight(fr):
    def mail(y, x, x0, x1, u):
        return (P["mail"][(x + y) % 2 + (1 if (x - x0) > (x1 - x0) * 0.6 else 0)], None)
    fill_body(fr, fr.neck + 1, fr.waist + 3, P["mail"], flare=0, folds=False, cols_fn=mail)
    fill_body(fr, fr.waist + 4, fr.boot_top - 1, P["trousers_dark"], flare=0)
    sleeves(fr, P["mail"])
    # the tabard: front and back panels down the middle to the knees, with an emblem on the chest (facing us)
    for y in range(fr.neck + 2, fr.knee + 1):
        sp = fr.span(y)
        if not sp:
            continue
        w = sp[1] - sp[0]
        x0 = sp[0] + int(w * 0.22)
        x1 = sp[1] - int(w * 0.22)
        for x in range(x0, x1 + 1):
            if fr.cls[y, x] in ("skin", "other") and y < fr.waist + 4:
                continue
            g = GREY[0] if x < x0 + 2 else (GREY[2] if x > x1 - 2 else GREY[1])
            fr.put(y, x, g, g)
        if fr.view in ("S", "SE") and fr.neck + 4 <= y <= fr.neck + 7:
            mid = (x0 + x1) // 2
            for x in (mid - 1, mid, mid + 1) if y in (fr.neck + 5, fr.neck + 6) else (mid,):
                fr.put(y, x, P["gold"][0])
    for y in (fr.waist + 2,):                                                            # the belt
        sp = fr.span(y)
        if sp:
            for x in range(sp[0], sp[1] + 1):
                fr.put(y, x, P["dark_leather"][1])
    for y in range(fr.neck, fr.neck + 3):                                                # shoulder guards
        sp = fr.span(y)
        if sp:
            for x in list(range(sp[0] - 1, sp[0] + 3)) + list(range(sp[1] - 2, sp[1] + 2)):
                fr.put(y, x, P["steel"][0] if y == fr.neck else P["steel"][1])
    head_cap(fr, P["steel"], 7)                                                          # the mail coif


def barbarian(fr):
    fill_body(fr, fr.neck + 1, fr.waist, P["skin"], flare=0, folds=False)               # bare chest
    # the harness: a strap from one shoulder across to the other hip
    for i in range(fr.waist - fr.neck):
        y = fr.neck + 1 + i
        sp = fr.span(y)
        if sp:
            x = int(sp[0] + (sp[1] - sp[0]) * (i / max(fr.waist - fr.neck, 1)))
            fr.put(y, x, P["dark_leather"][1])
            fr.put(y, x + 1, P["dark_leather"][2])
    # the hide kilt, from the waist to the knees, its hem ragged
    def ragged(y, x, x0, x1, u):
        if y >= fr.knee - 1 and (x * 7) % 3 == 0:
            return (P["hide"][2], None)
        return None
    fill_body(fr, fr.waist + 1, fr.knee, P["hide"], flare=2, cols_fn=ragged)
    sp = fr.span(fr.waist + 1)
    if sp:
        for x in range(sp[0], sp[1] + 1):
            fr.put(fr.waist + 1, x, GREY[1], GREY[1])                                   # its belt: accent
    sleeves(fr, P["skin"], bare=True)
    # the fur mantle: across the shoulders, a little wider than him, its lower edge in tufts
    for y in range(fr.neck - 1, fr.neck + 4):
        sp = fr.span(y)
        if not sp:
            continue
        for x in range(sp[0] - 2, sp[1] + 3):
            if y == fr.neck + 3 and (x % 2):
                continue
            fr.put(y, x, fr.tone(P["fur"], x, sp[0] - 2, sp[1] + 2))
    # fur tops on the boots
    for x in range(CELL):
        if fr.cls[fr.boot_top, x] == "boots":
            fr.put(fr.boot_top, x, P["fur"][0])


def ranger(fr):
    fill_body(fr, fr.neck + 1, fr.waist + 2, P["leather"], flare=0, folds=False)        # the jerkin
    fill_body(fr, fr.waist + 3, fr.boot_top - 1, P["green"], flare=0)                   # trousers
    sleeves(fr, P["green"], bracer=(P["dark_leather"][0], P["dark_leather"][2]))
    cloak_panels(fr, P["cloak_green"], fr.neck + 2, fr.bottom - 3)
    # the hood down: a rolled collar round the neck and shoulders, a scarf in it (accent)
    for y in range(fr.neck - 1, fr.neck + 2):
        sp = fr.span(y)
        if sp:
            for x in range(sp[0] - 1, sp[1] + 2):
                if y == fr.neck:
                    fr.put(y, x, GREY[1], GREY[1])
                else:
                    fr.put(y, x, P["cloak_green"][0] if y < fr.neck else P["cloak_green"][1])
    # the quiver on his back, seen from behind: slanting over his right shoulder, feathers at the top
    if fr.view in ("N", "NE"):
        for i in range(11):
            y = fr.neck - 2 + i
            x = int(fr.cx + 3 - i * 0.4)
            for dx in (0, 1, 2):
                fr.put(y, x + dx, P["dark_leather"][0] if dx < 2 else P["dark_leather"][2])
        for dx in (0, 1, 2, 3):
            fr.put(fr.neck - 3, int(fr.cx + 3) + dx, (220, 220, 210) if dx % 2 else (200, 70, 60))


def scout(fr):
    fill_body(fr, fr.neck + 1, fr.waist + 1, P["shirt"], flare=0, folds=False)          # the shirt
    for y in range(fr.neck + 1, fr.waist + 2):                                           # the open vest over it
        sp = fr.span(y)
        if not sp:
            continue
        w = sp[1] - sp[0]
        for x in range(sp[0], sp[1] + 1):
            t = (x - sp[0]) / max(w, 1)
            if (fr.view in ("S", "SE") and (t < 0.35 or t > 0.65)) or fr.view not in ("S", "SE"):
                if fr.cls[y, x] not in ("skin", "other"):
                    fr.put(y, x, fr.tone(P["ochre"], x, sp[0], sp[1]))
    fill_body(fr, fr.waist + 2, fr.boot_top - 1, P["trousers_dark"], flare=0)
    sleeves(fr, P["shirt"], cuff=(P["shirt"][2], None))
    # the satchel on his hip, with its strap across his chest
    sp = fr.span(fr.waist + 2)
    if sp:
        side = sp[1] if fr.back < 0 else sp[0]
        for y in range(fr.waist + 1, fr.waist + 6):
            for x in range(side - 2, side + 3):
                fr.put(y, x, P["leather"][0] if y == fr.waist + 1 else P["leather"][1])
        for i in range(fr.waist - fr.neck):
            y = fr.neck + 1 + i
            s2 = fr.span(y)
            if s2:
                x = int((s2[1] if side == sp[0] else s2[0]) + (side - (s2[1] if side == sp[0] else s2[0])) * i / max(fr.waist - fr.neck, 1))
                fr.put(y, x, P["dark_leather"][1])
    head_cap(fr, GREY, 5, accent=GREY[1])                                                # the bandana (accent)


def wizard(fr):
    def cloak_col(y, x, x0, x1, u):
        t = (x - x0) / max(x1 - x0, 1)
        if fr.view in ("N", "NE") and 0.15 < t < 0.85:
            return (P["grey_cloak"][0] if t < 0.5 else P["grey_cloak"][1], None)
        if t < 0.12 or t > 0.88:
            return (P["grey_cloak"][1], None)
        return None
    fill_body(fr, fr.neck, fr.bottom - 1, P["grey_robe"], flare=3, cols_fn=cloak_col)
    sleeves(fr, P["grey_robe"])
    rows = sorted(fr.spans)
    waist = min(rows[0] + 9, fr.bottom - 5) if rows else fr.waist
    sp = fr.span(waist)
    if sp:
        for x in range(sp[0], sp[1] + 1):
            fr.put(waist, x, P["rope"][0])
    fr.outline()
    hat(fr)


def shadow(fr):
    pal = P["night"]
    trim = (GREY[1], pal[0])
    def front_trim(y, x, x0, x1, u):
        if fr.view in ("S", "SE"):
            mid = (x0 + x1) // 2 + (1 if fr.view == "SE" else 0)
            if x == mid:
                return (GREY[1], GREY[1])
        t = (x - x0) / max(x1 - x0, 1)
        return (pal[0] if t < 0.15 else (pal[1] if t < 0.45 else (pal[2] if t < 0.8 else pal[3])), None)
    fill_body(fr, fr.neck, fr.bottom, P["night"], flare=3, cols_fn=front_trim)
    sleeves(fr, pal[1:], cuff=(GREY[1], GREY[1]))
    fr.outline()
    hood(fr, pal, trim)


LOOKS = {"brawler": brawler, "knight": knight, "barbarian": barbarian, "ranger": ranger, "scout": scout,
         "wizard": wizard, "shadow": shadow}


def paint(sheet, look):
    meta = json.load(open(os.path.join(ROOT, sheet + ".json")))
    src = np.array(Image.open(os.path.join(ROOT, sheet + ".png")).convert("RGBA"))
    out = src.copy()
    acc = np.zeros_like(src)
    for an in meta["animations"]:
        row, view = int(an["row"]), an["dir"]
        for f in range(int(an["frames"])):
            y0, x0 = row * CELL, f * CELL
            cell = out[y0:y0 + CELL, x0:x0 + CELL].copy()
            fr = Frame(cell, view)
            if fr.ok and not fr.lying:
                LOOKS[look](fr)
                fr.outline()
            elif fr.ok:   # lying down: just the garment's colour on his clothes
                fr.recolor(("tunic", "trousers", "scarf"), P["night"] if look == "shadow" else P["grey_robe"] if look == "wizard" else P["leather"])
            out[y0:y0 + CELL, x0:x0 + CELL] = fr.a
            acc[y0:y0 + CELL, x0:x0 + CELL] = fr.acc
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(out).save(os.path.join(OUT, "%s-%s.png" % (sheet, look)))
    Image.fromarray(acc).save(os.path.join(OUT, "%s-%s-accent.png" % (sheet, look)))


def main():
    for look in LOOKS:
        for sheet in ["pip-spritesheet", "pip-weapons"]:
            paint(sheet, look)
        print("wrote garb/*-%s.png (and -accent)" % look)


if __name__ == "__main__":
    main()
