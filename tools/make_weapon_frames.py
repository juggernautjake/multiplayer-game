"""Build Pip's weapon frames from his own sheet (assets/pip/pip-spritesheet.png, from 04-games/pip).

    python tools/make_weapon_frames.py        # writes assets/pip/pip-weapons.png + pip-weapons.json

* Sword: every club animation (stand, walk, run, air swings, backswing, smash) with the club recoloured: the end at
  the hand becomes a leather grip and a gold guard, the rest a steel blade, and the tip runs on a few pixels.
  The club is found exactly by its colours, which appear nowhere else on Pip.
* Bow and slingshot: Pip's punch pose (arm out). His fist is found per direction (the pixels that move out between
  the guard frame and the punch), and the weapon is drawn there in his outlined pixel style: 3 draw frames (string or
  band pulled further back, arrow or stone loaded) and 2 release frames. Seen from behind it is drawn behind him.

Same JSON layout as the main sheet (cell, anchor, directions, animations with row / frames / durationsMs / loop).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent.parent / "assets" / "pip"
SRC = Image.open(HERE / "pip-spritesheet.png").convert("RGBA")
META = json.loads((HERE / "pip-spritesheet.json").read_text(encoding="utf8"))
CW = CH = 64
A = np.array(SRC)
OUTLINE = (29, 22, 48, 255)
DIRS = ["S", "SE", "E", "NE", "N"]

CLUB = {  # club colour -> shade rank (0 light .. 1 dark)
    (0xd0, 0x93, 0x5a): 0.2, (0xa9, 0x6c, 0x3d): 0.45, (0x7a, 0x4a, 0x2a): 0.7, (0x4f, 0x2e, 0x1e): 0.9,
    (0xf3, 0xea, 0xd4): 0.0, (0x6e, 0x62, 0x4f): 0.8, (0xd8, 0xca, 0xa8): 0.1, (0xa8, 0x98, 0x7a): 0.5,
}
BLADE = [(0xf0, 0xf4, 0xf8), (0xc9, 0xd2, 0xdd), (0x9a, 0xa6, 0xb5), (0x6d, 0x78, 0x88)]
GRIP = [(0x7a, 0x4a, 0x2a), (0x4f, 0x2e, 0x1e)]
GOLD = [(0xf2, 0xc9, 0x4c), (0xb8, 0x8a, 0x1e)]
WOOD = [(0xb0, 0x78, 0x40), (0x7a, 0x4a, 0x2a)]
STRING = (0xe8, 0xe0, 0xc8)
BAND = (0xb0, 0x30, 0x30)
STONE = (0x8a, 0x8a, 0x92)
STEEL = (0xb8, 0xc2, 0xce)
FLETCH = (0xd0, 0x40, 0x40)


def cell(row: int, frame: int) -> np.ndarray:
    return A[row * CH:(row + 1) * CH, frame * CW:(frame + 1) * CW].copy()


def anim(name: str, d: str) -> dict:
    for a in META["animations"]:
        if a["name"] == name and a["dir"] == d:
            return a
    raise KeyError((name, d))


# ----------------------------------------------------------------------------- sword
def swordify(c: np.ndarray) -> np.ndarray:
    """Recolour the club in one cell into a sword and run the blade on past the club's end."""
    ys, xs = np.nonzero(np.array([[tuple(p[:3]) in CLUB and p[3] > 0 for p in row] for row in c]))
    if len(xs) < 3:
        return c
    pts = np.stack([xs, ys], 1).astype(float)
    # the body: opaque, non-club pixels; the club's hand end is the end nearer the body's centre
    body = np.argwhere((c[:, :, 3] > 0) & ~np.isin(np.arange(64 * 64).reshape(64, 64), ys * 64 + xs))
    bc = body[:, ::-1].mean(0) if len(body) else np.array([32.0, 40.0])
    mean = pts.mean(0)
    u, s, vt = np.linalg.svd(pts - mean)
    axis = vt[0]
    t = (pts - mean) @ axis
    if np.dot(axis, mean - bc) < 0:  # make +axis point away from the body (toward the tip)
        axis, t = -axis, -t
    t0, t1 = t.min(), t.max()
    length = max(t1 - t0, 1.0)
    out = c.copy()
    guard_t = t0 + 0.3 * length
    # 1) the grip stays (recoloured leather); the club's fat head is wiped out, with the outline that hugged it
    head = []
    for (x, y), ti in zip(pts.astype(int), t):
        shade = CLUB[tuple(c[y, x, :3])]
        if ti < guard_t:
            out[y, x, :3] = GRIP[0 if shade < 0.6 else 1]
        else:
            out[y, x] = (0, 0, 0, 0)
            head.append((x, y))
    for x, y in head:
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                yy, xx = y + dy, x + dx
                if 0 <= yy < 64 and 0 <= xx < 64 and tuple(out[yy, xx]) == OUTLINE:
                    near = out[max(0, yy - 1):yy + 2, max(0, xx - 1):xx + 2]
                    solid = [(tuple(p) != OUTLINE and p[3] > 0) for p in near.reshape(-1, 4)]
                    if not any(solid):
                        out[yy, xx] = (0, 0, 0, 0)
    before = out.copy()
    # 2) a straight blade along the same line: 2 px wide (bright edge, steel body), longer than the club, pointed
    nrm = np.array([-axis[1], axis[0]])
    base = mean + axis * guard_t
    blade_len = (t1 - guard_t) + 5.0
    for k in np.arange(0.0, blade_len, 0.5):
        p = base + axis * k
        put(out, p[0], p[1], BLADE[1], False)
        if k < blade_len - 1.5:
            q = p + nrm * 0.9
            put(out, q[0], q[1], BLADE[0], False)
    # 3) a gold crossguard across the line at the grip's end
    for k in (-2.0, -1.0, 0.0, 1.0, 2.0):
        g = base + nrm * k
        put(out, g[0], g[1], GOLD[0 if abs(k) < 2 else 1], False)
    _outline(out, before)
    return out


def _outline(out: np.ndarray, before: np.ndarray) -> None:
    """Pixels newly drawn get Pip's dark outline on their empty neighbours."""
    new = (out[:, :, 3] > 0) & (before[:, :, 3] == 0)
    ys, xs = np.nonzero(new)
    for y, x in zip(ys, xs):
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < 64 and 0 <= xx < 64 and out[yy, xx, 3] == 0:
                out[yy, xx] = OUTLINE


# ----------------------------------------------------------------------------- bow and slingshot
def fist(d: str) -> tuple[int, int, int]:
    """(row, frame, (x, y)) of the punch pose with the arm furthest out, and the fist position in it."""
    a = anim("jab", d)
    base = cell(a["row"], 0)
    best = None
    for f in range(a["frames"]):
        c = cell(a["row"], f)
        moved = (c[:, :, 3] > 0) & (base[:, :, 3] == 0)
        n = moved.sum()
        if best is None or n > best[0]:
            best = (n, f, moved)
    n, f, moved = best
    ys, xs = np.nonzero(moved)
    if d in ("E", "SE", "NE"):
        i = np.argmax(xs)
        return a["row"], f, (int(xs[i]) - 1, int(ys[i]))
    if len(xs):
        return a["row"], f, (int(round(xs.mean())), int(round(ys.mean())))
    return a["row"], f, (36, 38)


def put(out: np.ndarray, x: float, y: float, col, behind: bool) -> None:
    x, y = int(round(x)), int(round(y))
    if 0 <= x < 64 and 0 <= y < 64 and (not behind or out[y, x, 3] == 0):
        out[y, x] = (*col, 255)


def line(out, x0, y0, x1, y1, col, behind):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n + 1):
        t = i / max(n, 1)
        put(out, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, col, behind)


def draw_bow(c: np.ndarray, d: str, at, pull: float, loaded: bool) -> np.ndarray:
    """A short bow at the fist: limbs curving back toward Pip, the string pulled `pull` (0..1) back, an arrow if loaded."""
    out = c.copy()
    fx, fy = at
    side = {"E": 1.0, "SE": 0.7, "NE": 0.7, "S": 0.0, "N": 0.0}[d]   # how much of the bow's curve we see
    behind = d in ("N", "NE")
    half = 11
    tips = []
    for i in range(-half, half + 1):
        t = i / half
        x = fx - side * 3.0 * t * t
        put(out, x, fy + i, WOOD[0 if abs(t) < 0.5 else 1], behind)
        if abs(i) == half:
            tips.append((x, fy + i))
    back = side * (3.0 + 7.0 * pull)               # the nock point, pulled back toward Pip
    nock = (fx - back, fy)
    for tx, ty in tips:
        line(out, tx, ty, *nock, STRING, behind)
    if loaded:
        if side > 0.2:
            line(out, nock[0], fy, fx + 4, fy, WOOD[0], behind)
            put(out, fx + 5, fy, STEEL, behind)
            put(out, nock[0] - 1, fy - 1, FLETCH, behind)
            put(out, nock[0] - 1, fy + 1, FLETCH, behind)
        else:
            put(out, fx, fy, STEEL, behind)            # arrow pointing at (or away from) us: just its head
    _outline(out, c)
    return out


def draw_sling(c: np.ndarray, d: str, at, pull: float, loaded: bool) -> np.ndarray:
    """A Y-shaped slingshot at the fist, the band pulled `pull` back, a stone in it if loaded."""
    out = c.copy()
    fx, fy = at
    side = {"E": 1.0, "SE": 0.7, "NE": 0.7, "S": 0.0, "N": 0.0}[d]
    behind = d in ("N", "NE")
    line(out, fx, fy, fx, fy + 4, WOOD[1], behind)                  # handle
    line(out, fx, fy, fx - 3, fy - 5, WOOD[0], behind)              # prongs
    line(out, fx, fy, fx + 3, fy - 5, WOOD[0], behind)
    back = side * (2.0 + 7.0 * pull) + (1 - side) * 0.0
    pouch = (fx - back, fy - 3 + (1 - side) * 2 * pull)
    line(out, fx - 3, fy - 5, *pouch, BAND, behind)
    line(out, fx + 3, fy - 5, *pouch, BAND, behind)
    if loaded:
        put(out, pouch[0], pouch[1], STONE, behind)
        put(out, pouch[0] - 1, pouch[1], STONE, behind)
    _outline(out, c)
    return out


# ----------------------------------------------------------------------------- build
def main() -> None:
    rows, anims = [], []

    def add(name, d, cells, durs, loop):
        anims.append({"name": name, "group": "Weapons", "label": name, "dir": d, "row": len(rows), "frames": len(cells),
                      "durationsMs": durs, "events": [None] * len(cells), "loop": loop, "facesCamera": False})
        rows.append(cells)

    # sword: every club animation, recoloured
    for club in ("c_swing", "c_back", "c_smash", "wc_swing", "wc_back", "rc_swing", "ac_swing"):
        for d in DIRS:
            a = anim(club, d)
            add("s" + club[club.index("_"):] if club.startswith("c_") else club[0] + "s" + club[club.index("_"):], d,
                [swordify(cell(a["row"], f)) for f in range(a["frames"])], a["durationsMs"], a["loop"])

    # bow and slingshot: draw (3 frames, held on the last while charging) and release (2 frames)
    for d in DIRS:
        row, f, at = fist(d)
        pose = cell(row, f)
        guard = cell(row, 0)
        add("bowDraw", d, [draw_bow(pose, d, at, p, True) for p in (0.2, 0.6, 1.0)], [90, 90, 120], False)
        add("bowShot", d, [draw_bow(pose, d, at, 0.0, False), draw_bow(guard, d, (at[0] - 2, at[1] + 3), 0.0, False)], [110, 160], False)
        add("slingDraw", d, [draw_sling(pose, d, at, p, True) for p in (0.2, 0.6, 1.0)], [70, 70, 90], False)
        add("slingShot", d, [draw_sling(pose, d, at, 0.0, False), draw_sling(guard, d, (at[0] - 2, at[1] + 3), 0.0, False)], [90, 140], False)

    width = max(len(r) for r in rows) * CW
    sheet = Image.new("RGBA", (width, len(rows) * CH), (0, 0, 0, 0))
    for ri, cells in enumerate(rows):
        for fi, c in enumerate(cells):
            sheet.paste(Image.fromarray(c), (fi * CW, ri * CH))
    sheet.save(HERE / "pip-weapons.png")
    meta = {k: META[k] for k in ("character", "cell", "anchor", "directions")}
    meta["animations"] = anims
    (HERE / "pip-weapons.json").write_text(json.dumps(meta, indent=1), encoding="utf8")
    print(f"{len(rows)} rows, {sum(len(r) for r in rows)} frames -> {HERE / 'pip-weapons.png'}")


if __name__ == "__main__":
    main()
